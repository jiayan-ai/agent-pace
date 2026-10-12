import Foundation
import CryptoKit

public enum ClaudeUsageError: Error, LocalizedError {
    case notSignedIn, keychainPermission, expired, scopeMissing, invalidResponse, unavailable, network, ambiguousAccount
    case throttled(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "请打开 Claude 桌面应用并进入 Code，确认已登录后再点刷新。"
        case .keychainPermission:
            return "需要连接 Claude 桌面登录。点击「连接 Claude 桌面」，并在 macOS 提示时允许读取 Claude Safe Storage。"
        case .expired:
            return "Claude 桌面登录已过期。请打开 Claude 的 Code 页面，让应用更新登录状态后再点刷新。"
        case .scopeMissing:
            return "Claude 桌面当前登录无法读取订阅额度。请在 Claude 中检查账户，并进入 Code 后重试。"
        case .ambiguousAccount:
            return "Claude 桌面缓存了多个组织的登录。请在 Claude 中确认使用的账户后重试。"
        case .invalidResponse:
            return "暂时无法识别 Claude 额度数据。请稍后重试或更新 Claude Code。"
        case .unavailable:
            return "Claude 暂未返回可用的订阅额度。请确认已登录带额度的 Claude 账户。"
        case .network:
            return "Claude 额度同步失败。请检查网络，稍后重试。"
        case .throttled(let interval):
            return "Claude 额度查询暂时受限，约 \(max(1, Int(ceil(interval / 60)))) 分钟后自动重试。"
        }
    }
}

public struct ClaudeUsageResponse: Decodable {
    public struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?

        func normalized(minutes: Int) -> UsageWindow {
            var date: Date?
            if let resets_at {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = formatter.date(from: resets_at)
                if date == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = formatter.date(from: resets_at)
                }
            }
            return UsageWindow(usedPercent: utilization, windowDurationMins: minutes, resetsAt: date?.timeIntervalSince1970)
        }
    }

    let five_hour: Window?
    let seven_day: Window?
    let seven_day_sonnet: Window?
    let seven_day_opus: Window?

    public var normalized: UsageResponse {
        let main = UsageBucket(limitId: "claude", limitName: "Claude",
                              primary: seven_day?.normalized(minutes: 10080),
                              secondary: five_hour?.normalized(minutes: 300))
        var buckets = ["claude": main]
        if let seven_day_sonnet {
            buckets["claude_sonnet"] = UsageBucket(limitId: "claude_sonnet", limitName: "Claude Sonnet", primary: seven_day_sonnet.normalized(minutes: 10080))
        }
        if let seven_day_opus {
            buckets["claude_opus"] = UsageBucket(limitId: "claude_opus", limitName: "Claude Opus", primary: seven_day_opus.normalized(minutes: 10080))
        }
        return UsageResponse(rateLimits: main, rateLimitsByLimitId: buckets)
    }
}

private struct ClaudeProfile: Decodable {
    struct Identity: Decodable { let uuid: String }
    let account: Identity
    let organization: Identity
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class HTTPReply: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: (Data?, URLResponse?, Error?)?
    func put(_ value: (Data?, URLResponse?, Error?)) { lock.lock(); defer { lock.unlock() }; stored = value }
    func get() -> (Data?, URLResponse?, Error?)? { lock.lock(); defer { lock.unlock() }; return stored }
}

public enum ClaudeClient {
    /// Read the same subscription windows used by Claude Code's /usage screen.
    /// This is a private read-only endpoint, not a published stable third-party API.
    /// Tokens remain in memory; this client never rotates or writes Claude credentials.
    public static func fetch(allowKeychainPrompt: Bool = false) throws -> UsageSnapshot {
        let credential = try ClaudeDesktopLogin.read(allowPrompt: allowKeychainPrompt)
        let token = credential.token
        let usageData = try request(path: "/api/oauth/usage", token: token)
        let profileData = try request(path: "/api/oauth/profile", token: token)
        let profile: ClaudeProfile
        let usage: ClaudeUsageResponse
        do {
            profile = try JSONDecoder().decode(ClaudeProfile.self, from: profileData)
            usage = try JSONDecoder().decode(ClaudeUsageResponse.self, from: usageData)
        } catch { throw ClaudeUsageError.invalidResponse }
        guard profile.account.uuid.lowercased() == credential.account.lowercased(),
              profile.organization.uuid.lowercased() == credential.organization.lowercased() else {
            throw ClaudeUsageError.ambiguousAccount
        }
        let response = usage.normalized
        guard !response.windows.isEmpty else { throw ClaudeUsageError.unavailable }
        let identity = "claude/\(profile.organization.uuid)/\(profile.account.uuid)"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return UsageSnapshot(response: response, accountKey: hash, fetchedAt: Date())
    }

    private static func request(path: String, token: String) throws -> Data {
        let url = URL(string: "https://api.anthropic.com" + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentPace/1.3.0 (local usage viewer)", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let reply = HTTPReply(), done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            reply.put((data, response, error))
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + 26) == .success,
              let (data, rawResponse, error) = reply.get(), error == nil,
              let response = rawResponse as? HTTPURLResponse else { throw ClaudeUsageError.network }
        switch response.statusCode {
        case 200:
            guard let data, data.count < 1_000_000 else { throw ClaudeUsageError.invalidResponse }
            return data
        case 401: throw ClaudeUsageError.expired
        case 403: throw ClaudeUsageError.scopeMissing
        case 429:
            let seconds = TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 600
            throw ClaudeUsageError.throttled(max(300, min(3600, seconds)))
        default: throw ClaudeUsageError.network
        }
    }
}

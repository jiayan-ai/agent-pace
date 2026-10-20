import Foundation

/// Public announcements are deliberately separate from account snapshots and budgets.
public struct ResetRadarSnapshot: Codable {
    public let feed: ResetRadarFeed
    public let fetchedAt: Date

    public init(feed: ResetRadarFeed, fetchedAt: Date) {
        self.feed = feed
        self.fetchedAt = fetchedAt
    }

    public func isFresh(at now: Date) -> Bool {
        guard feed.status != "unknown",
              ["confirmed_today", "recorded_today", "no_verified_reset"].contains(feed.status),
              ResetRadarDate.isRecent(fetchedAt, at: now),
              ResetRadarDate.isRecent(feed.generatedDate, at: now),
              ResetRadarDate.isRecent(feed.archiveDate, at: now),
              let source = feed.sources?.first(where: { $0.id == "codex-resets" }),
              source.status == "online",
              ResetRadarDate.isRecent(ResetRadarDate.parse(source.checkedAt), at: now) else { return false }
        return true
    }

    public func assessment(at now: Date, calendar: Calendar = .current, failed: Bool = false) -> ResetRadarAssessment {
        let fresh = !failed && isFresh(at: now)
        guard fresh else {
            return ResetRadarAssessment(title: "Reset 动态待确认", detail: "来源尚未更新或连接失败；下面保留上次记录。", fresh: false, event: nil)
        }
        // The provider's *_today status uses UTC. Derive the user's day from event timestamps.
        let today = feed.records.filter {
            $0.preciseDate.map { $0 <= now && calendar.isDate($0, inSameDayAs: now) } == true
        }
        if let event = today.first(where: { $0.type == "global_reset" && $0.status != "planned" }) {
            return ResetRadarAssessment(title: "今日有全局 reset 记录", detail: "\(event.verificationLabel)；是否覆盖你的账户，以实际额度为准。", fresh: true, event: event)
        }
        if let event = feed.records.first(where: {
            $0.status == "planned" && $0.announcedDate.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 86400 } == true
        }) {
            return ResetRadarAssessment(title: "有新的 reset 预告", detail: "尚未确认执行，时间与适用范围请查看原帖。", fresh: true, event: event)
        }
        if let event = today.first(where: { $0.type == "banked_reset" && $0.status != "planned" }) {
            return ResetRadarAssessment(title: "今日有 reset 券发放记录", detail: "\(event.verificationLabel)；发券不等于额度已自动恢复。", fresh: true, event: event)
        }
        return ResetRadarAssessment(title: "今日尚无全局 reset 记录", detail: "追踪站暂未收录，不代表今天不会 reset。", fresh: true, event: nil)
    }
}

public struct ResetRadarAssessment {
    public let title: String
    public let detail: String
    public let fresh: Bool
    public let event: PublicResetEvent?
}

public struct ResetRadarFeed: Codable {
    public let status: String
    public let generatedAt: String
    public let resetArchiveSyncedAt: String?
    public let latestGlobalReset: PublicResetEvent?
    public let latestBankedReset: PublicResetEvent?
    public let events: [PublicResetEvent]?
    public let sources: [PublicResetSource]?

    public var generatedDate: Date? { ResetRadarDate.parse(generatedAt) }
    public var archiveDate: Date? { ResetRadarDate.parse(resetArchiveSyncedAt) }
    public var records: [PublicResetEvent] {
        var seen = Set<String>()
        return ((events ?? []) + [latestGlobalReset, latestBankedReset].compactMap { $0 })
            .filter { $0.isUsable && seen.insert($0.id).inserted }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    public func latest(_ type: String, at now: Date) -> PublicResetEvent? {
        records.first { $0.type == type && $0.status != "planned" && ($0.date ?? .distantFuture) <= now }
    }

    public static func decode(_ data: Data) throws -> ResetRadarFeed {
        guard data.count <= ResetRadarClient.maximumBytes else { throw ResetRadarError.invalidResponse }
        let feed: ResetRadarFeed
        do { feed = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw ResetRadarError.invalidResponse }
        guard feed.generatedDate != nil else { throw ResetRadarError.invalidResponse }
        return feed
    }
}

public struct PublicResetSource: Codable {
    public let id: String
    public let status: String
    public let checkedAt: String?
    enum CodingKeys: String, CodingKey { case id, status; case checkedAt = "checked_at" }
}

public struct PublicResetEvent: Codable, Identifiable {
    public let id: String
    public let type: String
    public let status: String
    public let announcedAt: String?
    public let effectiveAt: String?
    public let timePrecision: String?
    public let timeBasis: String?
    public let sourceURLString: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case id, type, status, scope
        case announcedAt = "announced_at", effectiveAt = "effective_at"
        case timePrecision = "time_precision", timeBasis = "time_basis", sourceURLString = "source_url"
    }
    public var announcedDate: Date? { ResetRadarDate.parse(announcedAt) }
    public var date: Date? { announcedDate ?? ResetRadarDate.parse(effectiveAt) }
    public var preciseDate: Date? {
        guard timePrecision == "minute" || timePrecision == "second", (announcedAt ?? effectiveAt)?.contains("T") == true else { return nil }
        return date
    }
    public var dateOnlyLabel: String? {
        guard preciseDate == nil, let raw = announcedAt ?? effectiveAt, date != nil else { return nil }
        return String(raw.prefix(10)) + "（UTC 日期）"
    }
    public var sourceURL: URL? { ResetRadarLinks.evidence(sourceURLString) }
    public var isUsable: Bool {
        !id.isEmpty && ["global_reset", "banked_reset"].contains(type)
            && ["confirmed", "recorded", "planned"].contains(status) && date != nil && sourceURL != nil
    }
    public var kindLabel: String { type == "banked_reset" ? "Reset 券发放" : "全局 reset" }
    public var verificationLabel: String {
        switch status {
        case "confirmed": return "追踪站已核验"
        case "planned": return "预告 · 待执行"
        default: return "社区收录 · 未独立核验"
        }
    }
    public var timeLabel: String {
        if announcedAt != nil { return "公告时间" }
        return timeBasis == "observation" ? "观察时间" : "记录时间"
    }
}

public enum ResetRadarDate {
    public static func parse(_ value: String?) -> Date? {
        guard let value, value.count <= 40 else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        day.isLenient = false
        guard value.count == 10, let date = day.date(from: value), day.string(from: date) == value else { return nil }
        return date
    }
    static func isRecent(_ value: Date?, at now: Date) -> Bool {
        guard let value else { return false }
        let age = now.timeIntervalSince(value)
        return age >= -300 && age <= 30 * 60
    }
}

public enum ResetRadarLinks {
    public static let tracker = URL(string: "https://codexreset.dev/")!
    public static let forecast = URL(string: "https://willcodexreset.com/")!
    public static let tibo = URL(string: "https://x.com/thsottiaux")!

    public static func evidence(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return nil }
        if ["x.com", "twitter.com", "www.x.com", "www.twitter.com"].contains(host) {
            let parts = url.path.split(separator: "/")
            guard parts.count == 3, parts[0].lowercased() == "thsottiaux", parts[1] == "status",
                  !parts[2].isEmpty, parts[2].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        } else if !["openai.com", "help.openai.com", "learn.chatgpt.com"].contains(host) { return nil }
        return url
    }
}

public enum ResetRadarError: LocalizedError {
    case unavailable, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Reset 动态暂时无法同步，稍后自动重试。"
        case .invalidResponse: return "Reset 来源格式有变化，暂时无法确认新动态。"
        }
    }
}

public enum ResetRadarClient {
    public static let maximumBytes = 1_048_576
    public static let refreshInterval: TimeInterval = 15 * 60
    public static let minimumInterval: TimeInterval = 60
    public static let endpoint = URL(string: "https://codexreset.dev/api/status?lang=zh")!
    public typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)

    public static func fetch(transport: Transport = download) async throws -> ResetRadarSnapshot {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentPace/1.4 (public reset tracker)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw ResetRadarError.unavailable }
        guard response.statusCode == 200, response.url?.host == endpoint.host,
              response.url?.scheme == "https" else { throw ResetRadarError.unavailable }
        return ResetRadarSnapshot(feed: try ResetRadarFeed.decode(data), fetchedAt: Date())
    }

    public static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: ResetRadarRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= maximumBytes else { throw ResetRadarError.unavailable }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw ResetRadarError.invalidResponse }
            data.append(byte)
        }
        return (data, http)
    }
}

private final class ResetRadarRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A feed never needs to redirect to a login page or a different service.
        completionHandler(nil)
    }
}

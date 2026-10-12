import Foundation

public enum ClaudeUsageError: Error, LocalizedError {
    case notSignedIn, expired, scopeMissing, invalidResponse, unavailable, network, ambiguousAccount
    case throttled(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn, .expired:
            return "请点击「连接 Claude」，在工具的网页窗口中登录一次；不需要 Mac 钥匙串密码。"
        case .scopeMissing:
            return "Claude 需要验证登录。请在连接窗口中完成网页验证，再点「同步额度」。"
        case .ambiguousAccount:
            return "请选择要同步的 Claude 组织，然后再同步额度。"
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

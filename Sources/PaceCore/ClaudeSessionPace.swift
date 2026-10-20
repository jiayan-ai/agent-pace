import Foundation

/// A rolling allowance for Claude's five-hour session, independent of daily baselines.
public struct ClaudeSessionPace {
    public let remaining: Double?
    public let resetDate: Date?
    public let secondsRemaining: TimeInterval?

    public init(window: UsageWindow, now: Date) {
        guard window.windowDurationMins == 300 else {
            remaining = nil
            resetDate = nil
            secondsRemaining = nil
            return
        }
        remaining = window.remaining
        if let reset = window.resetsAt, reset.isFinite, now.timeIntervalSince1970.isFinite {
            resetDate = Date(timeIntervalSince1970: reset)
            secondsRemaining = reset - now.timeIntervalSince1970
        } else {
            resetDate = nil
            secondsRemaining = nil
        }
    }

    public var awaitingReset: Bool { secondsRemaining.map { $0 <= 0 } ?? false }
    public var isFinalHour: Bool { secondsRemaining.map { $0 > 0 && $0 < 3600 } ?? false }

    /// Percentage points per hour; in the final partial hour, all remaining
    /// points are available until reset, and the UI must label that interval.
    public var allowance: Double? {
        guard let remaining, let secondsRemaining, secondsRemaining > 0 else { return nil }
        return remaining / max(1, secondsRemaining / 3600)
    }

    public var heading: String { isFinalHour ? "重置前还可以用" : "接下来每小时建议可用" }
    public var unit: String { isFinalHour ? "%" : "% / 小时" }
    public var countdown: String {
        guard let secondsRemaining else { return "重置时间未知" }
        guard secondsRemaining > 0 else { return "等待重置确认" }
        if secondsRemaining < 60 { return "不足 1 分钟" }
        // Round up so the countdown never claims a reset happened early.
        let minutes = ceil(secondsRemaining / 60)
        let hours = floor(minutes / 60)
        let rest = minutes.truncatingRemainder(dividingBy: 60)
        return hours > 0 ? String(format: "%.0f 小时 %.0f 分钟", hours, rest)
            : String(format: "%.0f 分钟", minutes)
    }

    public func menuTitle(stale: Bool) -> String {
        guard let allowance else { return awaitingReset ? "Claude 待重置" : "Claude 待同步" }
        return "Claude \(stale ? "≈" : "")\(String(format: "%.1f", allowance))\(isFinalHour ? "% · <1h" : "%/h")"
    }
}

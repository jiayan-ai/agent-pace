import Foundation
import PaceCore

struct ClaudeSessionTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-20T23:30:00Z")!

    private func window(used: Double? = 40, seconds: Double = 10800) -> UsageWindow {
        UsageWindow(usedPercent: used, windowDurationMins: 300,
                    resetsAt: now.addingTimeInterval(seconds).timeIntervalSince1970)
    }

    func testRollingHourlyAllowanceAndMidnight() throws {
        let quota = window()
        let initial = ClaudeSessionPace(window: quota, now: now)
        try expect(initial.allowance == 20)
        try expect(initial.countdown == "3 小时 0 分钟")
        try expect(initial.menuTitle(stale: false) == "Claude 20.0%/h")
        try expect(initial.menuTitle(stale: true) == "Claude ≈20.0%/h")
        // The same window crosses midnight without a daily baseline reset.
        let later = ClaudeSessionPace(window: quota, now: now.addingTimeInterval(3600))
        try expect(later.allowance == 30)
        let updated = ClaudeSessionPace(window: window(used: 60), now: now.addingTimeInterval(3600))
        try expect(updated.allowance == 20)
        try expect(updated.remaining == 40 && updated.countdown == "2 小时 0 分钟")
    }

    func testFinalHourAndCountdownBoundaries() throws {
        let fullHour = ClaudeSessionPace(window: window(seconds: 3600), now: now)
        try expect(!fullHour.isFinalHour && fullHour.allowance == 60)
        let finalHour = ClaudeSessionPace(window: window(seconds: 3599), now: now)
        try expect(finalHour.isFinalHour && finalHour.allowance == 60)
        try expect(finalHour.heading == "重置前还可以用" && finalHour.unit == "%")
        try expect(finalHour.menuTitle(stale: false) == "Claude 60.0% · <1h")
        let halfHour = ClaudeSessionPace(window: window(seconds: 1800), now: now)
        try expect(halfHour.allowance == 60 && halfHour.countdown == "30 分钟")
        let lastSecond = ClaudeSessionPace(window: window(seconds: 0.1), now: now)
        try expect(lastSecond.allowance == 60 && lastSecond.countdown == "不足 1 分钟")
        for seconds in [0.0, -1, -3600] {
            let expired = ClaudeSessionPace(window: window(seconds: seconds), now: now)
            try expect(expired.awaitingReset && expired.allowance == nil)
            try expect(expired.countdown == "等待重置确认")
            try expect(expired.menuTitle(stale: false) == "Claude 待重置")
        }
    }

    func testUnknownExhaustedAndNewSession() throws {
        for used in [nil, Double.nan, Double.infinity] {
            let pace = ClaudeSessionPace(window: window(used: used), now: now)
            try expect(pace.allowance == nil && pace.remaining == nil)
            try expect(pace.countdown == "3 小时 0 分钟")
        }
        for reset in [nil, Double.nan, Double.infinity] {
            let pace = ClaudeSessionPace(window: UsageWindow(usedPercent: 40, windowDurationMins: 300, resetsAt: reset), now: now)
            try expect(pace.allowance == nil && pace.resetDate == nil)
            try expect(pace.countdown == "重置时间未知")
        }
        let exhausted = ClaudeSessionPace(window: window(used: 100), now: now)
        try expect(exhausted.allowance == 0 && !exhausted.awaitingReset)
        let newSession = ClaudeSessionPace(window: window(used: 0, seconds: 5 * 3600), now: now)
        try expect(newSession.remaining == 100 && newSession.allowance == 20)
        for duration in [nil, 0, 10080] {
            let pace = ClaudeSessionPace(window: UsageWindow(usedPercent: 40, windowDurationMins: duration,
                resetsAt: now.addingTimeInterval(3600).timeIntervalSince1970), now: now)
            try expect(pace.allowance == nil)
        }
    }
}

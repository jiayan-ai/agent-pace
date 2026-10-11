import Foundation
import PaceCore

struct BudgetTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
    private func window(_ used: Double?, days: Double = 7, reset: Double? = nil) -> UsageWindow {
        UsageWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: reset ?? now.addingTimeInterval(days * 86400).timeIntervalSince1970)
    }
    func testDailyAllowanceAndOneForOneSubtraction() throws {
        let first = try require(DailyBudget.reconcile(previous: nil, window: window(30), now: now, calendar: calendar))
        try expect(abs((first.leftToday) - (10)) <= 0.0001)
        let updated = try require(DailyBudget.reconcile(previous: first, window: window(34), now: now.addingTimeInterval(120), calendar: calendar))
        try expect(abs((updated.allowance) - (10)) <= 0.0001)
        try expect(abs((updated.leftToday) - (6)) <= 0.0001)
        try expect((updated.startedAt) == (first.startedAt))
    }
    func testSpendingBeyondBudgetShowsNegativeBalance() throws {
        let first = DailyBudget.reconcile(previous: nil, window: window(30), now: now, calendar: calendar)
        let updated = try require(DailyBudget.reconcile(previous: first, window: window(47), now: now, calendar: calendar))
        try expect(abs(updated.leftToday - (-7)) <= 0.0001)
        try expect(abs((updated.overBudget) - (7)) <= 0.0001)
        let tomorrow = try require(DailyBudget.reconcile(previous: updated, window: window(47), now: now.addingTimeInterval(86400), calendar: calendar))
        try expect(abs(tomorrow.leftToday - (53.0 / 6.0)) <= 0.0001)
    }
    func testFractionalDaysAndFinalHours() throws {
        try expect(abs((try require(DailyBudget.reconcile(previous: nil, window: window(10, days: 4.5), now: now)).allowance) - (20)) <= 0.0001)
        try expect(abs((try require(DailyBudget.reconcile(previous: nil, window: window(75, days: 0.25), now: now)).allowance) - (25)) <= 0.0001)
    }
    func testNextDayRebalancesRemaining() throws {
        let first = DailyBudget.reconcile(previous: nil, window: window(30), now: now, calendar: calendar)
        let next = try require(DailyBudget.reconcile(previous: first, window: window(40), now: now.addingTimeInterval(86400), calendar: calendar))
        try expect(abs((next.allowance) - (10)) <= 0.0001)
        try expect((next.consumed) == (0))
    }
    func testResetAndUsageDecreaseStartFreshBudget() throws {
        let first = DailyBudget.reconcile(previous: nil, window: window(60), now: now, calendar: calendar)
        let renewed = try require(DailyBudget.reconcile(previous: first, window: window(5, days: 6), now: now, calendar: calendar))
        try expect((renewed.startingUsed) == (5))
        let corrected = try require(DailyBudget.reconcile(previous: first, window: window(50), now: now, calendar: calendar))
        try expect((corrected.startingUsed) == (50))
    }
    func testMissingExpiredAndExhaustedData() throws {
        try expect((DailyBudget.reconcile(previous: nil, window: window(nil), now: now)) == nil)
        try expect((DailyBudget.reconcile(previous: nil, window: window(10, days: 0), now: now)) == nil)
        try expect((DailyBudget.reconcile(previous: nil, window: UsageWindow(usedPercent: 10, windowDurationMins: nil, resetsAt: now.timeIntervalSince1970 + 200), now: now)) == nil)
        try expect((try require(DailyBudget.reconcile(previous: nil, window: window(110), now: now)).leftToday) == (0))
        try expect((window(-10).remaining) == (100))
    }
    func testBudgetSurvivesPersistence() throws {
        let first = try require(DailyBudget.reconcile(previous: nil, window: window(30), now: now))
        let restored = try JSONDecoder().decode(DailyBudget.self, from: JSONEncoder().encode(first))
        try expect((restored) == (first))
        try expect(abs((try require(DailyBudget.reconcile(previous: restored, window: window(35), now: now)).leftToday) - (5)) <= 0.0001)
    }
    func testDayBoundaryAndTimezoneChange() throws {
        let justBeforeMidnight = calendar.startOfDay(for: now).addingTimeInterval(86399)
        let reset = justBeforeMidnight.addingTimeInterval(7 * 86400).timeIntervalSince1970
        let first = DailyBudget.reconcile(previous: nil, window: window(30, reset: reset), now: justBeforeMidnight, calendar: calendar)
        let next = try require(DailyBudget.reconcile(previous: first, window: window(35, reset: reset), now: justBeforeMidnight.addingTimeInterval(2), calendar: calendar))
        try expect((next.consumed) == (0))
        var other = calendar
        other.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let moved = try require(DailyBudget.reconcile(previous: first, window: window(35, reset: reset), now: justBeforeMidnight, calendar: other))
        try expect((moved.timeZoneID) == ("America/Los_Angeles"))
        try expect((moved.startingUsed) == (35))
    }
    func testMultipleBucketsPreferredAndLongestCodexWindowFirst() throws {
        let json = #"{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99,"windowDurationMins":60,"resetsAt":2000000000}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":4,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000000}},"other":{"primary":{"usedPercent":60,"windowDurationMins":43200,"resetsAt":2000000000}}}}"#
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        try expect((response.windows.count) == (3))
        try expect((response.windows.first?.id) == ("codex/secondary"))
        try expect(!(response.windows.contains { $0.bucketID == "legacy" }))
    }
    func testLegacyAndNullFields() throws {
        let json = #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":null,"windowDurationMins":10080,"resetsAt":null},"secondary":null},"rateLimitsByLimitId":null}"#
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        try expect((response.windows.count) == (1))
        try expect((response.windows[0].window.remaining) == nil)
        try expect((response.windows[0].window.resetDate) == nil)
    }
}

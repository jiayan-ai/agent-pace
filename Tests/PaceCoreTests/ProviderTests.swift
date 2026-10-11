import Foundation
import PaceCore

struct ProviderTests {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let account = "11111111-1111-4111-8111-111111111111"
    let org = "22222222-2222-4222-8222-222222222222"

    func testClaudeWindowsAndDates() throws {
        let json = #"{"five_hour":{"utilization":27.5,"resets_at":"2026-10-12T05:00:00Z"},"seven_day":{"utilization":12.25,"resets_at":"2026-10-17T01:00:00.123Z"},"seven_day_sonnet":null,"seven_day_opus":{"utilization":8,"resets_at":"2026-10-17T01:00:00Z"},"extra_usage":{"is_enabled":true}}"#
        let windows = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8)).normalized.windows
        try expect(windows.count == 3)
        try expect(windows[0].id == "claude/primary")
        try expect(windows[0].window.windowDurationMins == 10080)
        try expect(windows[0].window.remaining == 87.75)
        try expect(windows[1].window.windowDurationMins == 300)
        try expect(windows[1].window.remaining == 72.5)
        let whole = ISO8601DateFormatter().date(from: "2026-10-17T01:00:00Z")!.timeIntervalSince1970
        try expect(abs(try require(windows[0].window.resetsAt) - whole - 0.123) < 0.001)
    }

    func testClaudeMissingResetDoesNotInventBudget() throws {
        let json = #"{"five_hour":null,"seven_day":{"utilization":0,"resets_at":null}}"#
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8)).normalized
        try expect(response.windows.count == 1)
        try expect(DailyBudget.reconcile(previous: nil, window: response.windows[0].window, now: date) == nil)
        let empty = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data("{}".utf8)).normalized
        try expect(empty.windows.isEmpty)
        try expectThrows { try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(#"{"seven_day":{"utilization":"bad"}}"#.utf8)) }
    }

    func snapshot(_ used: Double, identity: String = "account-a") -> UsageSnapshot {
        let window = UsageWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: date.addingTimeInterval(7 * 86400).timeIntervalSince1970)
        let response = UsageResponse(rateLimits: UsageBucket(limitId: "same-id", limitName: "Test", primary: window))
        return UsageSnapshot(response: response, accountKey: identity, fetchedAt: date)
    }

    func testProviderIsolationAndPersistence() throws {
        var history = PaceHistory()
        history[.codex].ingest(snapshot(30))
        let codex = try require(history[.codex].budgets.values.first)
        history.selectedProvider = .claude
        history[.claude].ingest(snapshot(80))
        history[.codex].ingest(snapshot(45)) // late Codex completion after toggle
        try expect(history.selectedProvider == .claude)
        try expect(history[.claude].budgets.values.first?.startingUsed == 80)
        try expect(history[.codex].budgets.values.first?.allowance == codex.allowance)
        try expect(history[.codex].budgets.values.first?.leftToday == -5)
        history[.claude].ingest(snapshot(20, identity: "account-b"))
        try expect(history[.claude].budgets.values.first?.consumed == 0)
        try expect(history[.codex].budgets.values.first?.leftToday == -5)
        let restored = try JSONDecoder().decode(PaceHistory.self, from: JSONEncoder().encode(history))
        try expect(restored.selectedProvider == .claude)
        try expect(restored[.codex].budgets == history[.codex].budgets)
        try expect(restored[.claude].budgets == history[.claude].budgets)
    }

    func testLegacyMigrationPreservesNegativeBalance() throws {
        var old = ProviderHistory()
        old.ingest(snapshot(30)); old.ingest(snapshot(45))
        let restored = try JSONDecoder().decode(PaceHistory.self, from: JSONEncoder().encode(old))
        try expect(restored.selectedProvider == .codex)
        try expect(restored[.codex].budgets.values.first?.leftToday == -5)
        try expect(restored[.codex].selectedID == old.selectedID)
        try expect(restored[.claude].snapshot == nil)
    }

    func testResetTimestampJitterKeepsDailySpending() throws {
        let first = snapshot(30)
        let window = first.response.windows[0].window
        let initial = try require(DailyBudget.reconcile(previous: nil, window: window, now: date))
        let jittered = UsageWindow(usedPercent: 45, windowDurationMins: 10080, resetsAt: window.resetsAt! + 0.8)
        let updated = try require(DailyBudget.reconcile(previous: initial, window: jittered, now: date.addingTimeInterval(300)))
        try expect(updated.allowance == initial.allowance)
        try expect(updated.startedAt == initial.startedAt)
        try expect(updated.leftToday == -5)
        let newCycle = UsageWindow(usedPercent: 45, windowDurationMins: 10080, resetsAt: window.resetsAt! + 86400)
        let reset = try require(DailyBudget.reconcile(previous: updated, window: newCycle, now: date.addingTimeInterval(600)))
        try expect(reset.consumed == 0)
    }

    func cache(organization: String? = nil, accountID: String? = nil, host: String = "https://api.anthropic.com", expired: Bool = false) -> [String: [String: Any]] {
        let key = "acct:\(accountID ?? account)|client:\(organization ?? org):\(host):user:inference user:profile user:sessions:claude_code"
        return [key: ["token": "synthetic-fixture", "expiresAt": date.addingTimeInterval(expired ? -1 : 3600).timeIntervalSince1970 * 1000]]
    }

    func testDesktopCredentialIdentityAndExpiry() throws {
        func encoded(_ cache: [String: [String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: cache) }
        let credential = try ClaudeDesktopLogin.credential(from: encoded(cache()), account: account, now: date)
        try expect(credential.account == account && credential.organization == org)
        try expectThrows { try ClaudeDesktopLogin.credential(from: encoded(cache(expired: true)), account: account, now: date) }
        try expectThrows { try ClaudeDesktopLogin.credential(from: encoded(cache(accountID: org)), account: account, now: date) }
        try expectThrows { try ClaudeDesktopLogin.credential(from: encoded(cache(host: "https://example.com")), account: account, now: date) }
        var ambiguous = cache()
        ambiguous.merge(cache(organization: account)) { _, new in new }
        try expectThrows { try ClaudeDesktopLogin.credential(from: encoded(ambiguous), account: account, now: date) }
    }

    func testDesktopEncryptionFixture() throws {
        // Fixture independently produced with OpenSSL AES-128-CBC + Python PBKDF2.
        let encrypted = Data(base64Encoded: "djEww2Eb9+v/+ttq7ayrFzwVkAGDy82X1F8NmAv2Voth6/0=")!
        let decoded = try ClaudeDesktopLogin.decrypt(encrypted, password: Data("fixture-password".utf8))
        try expect(String(data: decoded, encoding: .utf8) == #"{"fixture":"desktop-login"}"#)
        // CBC is not authenticated: a wrong key can happen to have valid padding.
        // The following JSON/account validation must still reject its plaintext.
        let wrong = try? ClaudeDesktopLogin.decrypt(encrypted, password: Data("wrong-password".utf8))
        try expect(wrong != decoded)
        if let wrong {
            try expectThrows { try ClaudeDesktopLogin.credential(from: wrong, account: account, now: date) }
        }
        try expectThrows { try ClaudeDesktopLogin.decrypt(Data("v20unknown".utf8), password: Data()) }
    }
}

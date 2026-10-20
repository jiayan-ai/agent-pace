import Foundation
import PaceCore

struct ResetRadarTests {
    let now = ResetRadarDate.parse("2026-10-19T10:15:00Z")!
    var local: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }
    func event(_ type: String = "global_reset", status: String = "recorded", date: String = "2026-10-19T09:00:00Z", precision: String = "minute") -> [String: Any] {
        ["id": "fixture-\(type)-\(date)", "type": type, "status": status, "announced_at": date,
         "effective_at": date, "time_precision": precision, "time_basis": "announcement",
         "source_url": "https://x.com/thsottiaux/status/123456789", "scope": "Eligible accounts"]
    }
    func payload(events: [[String: Any]] = [], status: String = "no_verified_reset", updated: String = "2026-10-19T10:10:00Z", sourceStatus: String = "online") -> [String: Any] {
        ["status": status, "generatedAt": "2026-10-19T10:15:00.000Z", "resetArchiveSyncedAt": updated,
         "events": events, "sources": [["id": "codex-resets", "status": sourceStatus, "checked_at": updated]],
         "forecast": ["probability_24h": NSNull(), "probability_48h": NSNull()]]
    }
    func snapshot(_ payload: [String: Any]) throws -> ResetRadarSnapshot {
        ResetRadarSnapshot(feed: try ResetRadarFeed.decode(JSONSerialization.data(withJSONObject: payload)), fetchedAt: now)
    }
    func testRecordedConfirmedAndBankedAreDistinct() throws {
        let recorded = try snapshot(payload(events: [event()])).assessment(at: now, calendar: local)
        try expect(recorded.title == "今日有全局 reset 记录")
        try expect(recorded.detail.contains("未独立核验"))
        let confirmed = try snapshot(payload(events: [event(status: "confirmed")])).assessment(at: now, calendar: local)
        try expect(confirmed.detail.contains("追踪站已核验"))
        let banked = try snapshot(payload(events: [event("banked_reset")])).assessment(at: now, calendar: local)
        try expect(banked.title == "今日有 reset 券发放记录")
        try expect(banked.detail.contains("不等于额度已自动恢复"))
    }
    func testTodayUsesLocalDayInsteadOfUpstreamUTCStatus() throws {
        let value = try snapshot(payload(events: [event(date: "2026-10-19T01:00:00Z")], status: "confirmed_today"))
        try expect(value.assessment(at: now, calendar: local).event == nil)
        var utc = local; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        try expect(value.assessment(at: now, calendar: utc).event != nil)
        // Across UTC midnight, a record on yesterday's UTC date may still be today locally.
        let beforeLocalMidnight = ResetRadarDate.parse("2026-10-19T00:15:00Z")!
        var p = payload(events: [event(date: "2026-10-18T23:30:00Z")], updated: "2026-10-19T00:10:00Z")
        p["generatedAt"] = "2026-10-19T00:15:00Z"
        let v = ResetRadarSnapshot(feed: try snapshot(p).feed, fetchedAt: beforeLocalMidnight)
        try expect(v.assessment(at: beforeLocalMidnight, calendar: local).event != nil)
        // Both occurrences of 01:30 on the autumn DST transition belong to the same local day.
        try expect(local.isDate(ResetRadarDate.parse("2026-11-01T08:30:00Z")!, inSameDayAs: ResetRadarDate.parse("2026-11-01T09:30:00Z")!))
    }
    func testFreshHTTPDoesNotHideStaleOrFailedSource() throws {
        try expect(!snapshot(payload(updated: "2026-10-19T08:00:00Z")).isFresh(at: now))
        try expect(!snapshot(payload(sourceStatus: "error")).isFresh(at: now))
        try expect(!snapshot(payload(status: "unknown")).isFresh(at: now))
        try expect(!snapshot(payload(status: "new-unrecognized-state")).isFresh(at: now))
        try expect(!snapshot(payload(updated: "2026-10-20T10:00:00Z")).isFresh(at: now))
        var missing = payload(); missing.removeValue(forKey: "resetArchiveSyncedAt")
        try expect(!snapshot(missing).isFresh(at: now))
        missing = payload(); missing["sources"] = [["id": "openai-status", "status": "online", "checked_at": "2026-10-19T10:10:00Z"]]
        try expect(!snapshot(missing).isFresh(at: now))
        let value = try snapshot(payload(events: [event()]))
        try expect(value.isFresh(at: now))
        try expect(!value.assessment(at: now, failed: true).fresh)
        try expect(value.assessment(at: now, failed: true).event == nil)
        try expect(!value.isFresh(at: now.addingTimeInterval(35 * 60)))
    }
    func testPlannedFutureAndDateOnlyNeverClaimDelivery() throws {
        var planned = event(status: "planned")
        planned["effective_at"] = "2026-10-19T18:00:00Z"
        let value = try snapshot(payload(events: [planned]))
        try expect(value.assessment(at: now, calendar: local).title == "有新的 reset 预告")
        try expect(value.feed.latest("global_reset", at: now) == nil)
        let future = try snapshot(payload(events: [event(status: "confirmed", date: "2026-10-20T09:00:00Z")]))
        try expect(future.assessment(at: now, calendar: local).event == nil)
        try expect(future.feed.latest("global_reset", at: now) == nil)
        let day = try snapshot(payload(events: [event(date: "2026-10-19", precision: "day")]))
        try expect(day.assessment(at: now, calendar: local).event == nil)
        try expect(day.feed.records.first?.dateOnlyLabel == "2026-10-19（UTC 日期）")
        try expect(ResetRadarDate.parse("2026-02-30") == nil)
    }
    func testUnknownRecordsAndUntrustedLinksAreExcluded() throws {
        var bad = event(); bad["source_url"] = "https://x.com.evil.example/thsottiaux/status/123"
        var noDate = event(); noDate["announced_at"] = NSNull(); noDate["effective_at"] = NSNull()
        let value = try snapshot(payload(events: [bad, noDate, event(status: "rumor"), event("personal_reset")]))
        try expect(value.feed.records.isEmpty)
        for url in ["file:///tmp/a", "javascript:alert(1)", "https://x.com@evil.example/a", "https://user@x.com/thsottiaux/status/12",
                    "https://x.com/another/status/12", "https://x.com/thsottiaux/status/12/extra", "http://x.com/thsottiaux/status/12"] {
            try expect(ResetRadarLinks.evidence(url) == nil)
        }
        try expect(ResetRadarLinks.evidence("https://x.com/thsottiaux/status/12") != nil)
        try expect(ResetRadarLinks.evidence("https://learn.chatgpt.com/docs/changelog#june-2026") != nil)
    }
    func testCacheAndMalformedResponses() throws {
        var p = payload(events: [event(), event()])
        p["latestGlobalReset"] = event()
        let value = try snapshot(p)
        try expect(value.feed.records.count == 1)
        let cache = try JSONDecoder().decode(ResetRadarSnapshot.self, from: JSONEncoder().encode(value))
        try expect(cache.feed.records.count == 1 && cache.fetchedAt == value.fetchedAt)
        try expect(!cache.isFresh(at: now.addingTimeInterval(3600)))
        for body in ["<html>error</html>", "{}", "{\"status\":\"confirmed_today\",\"generatedAt\":\"bad\"}"] {
            try expectThrows { try ResetRadarFeed.decode(Data(body.utf8)) }
        }
        try expectThrows { try ResetRadarFeed.decode(Data(repeating: 32, count: ResetRadarClient.maximumBytes + 1)) }
    }
    func testPublicTransportAndFailureHandling() async throws {
        let data = try JSONSerialization.data(withJSONObject: payload(events: [event()]))
        let value = try await ResetRadarClient.fetch { request in
            try expect(request.url == ResetRadarClient.endpoint)
            try expect(request.httpMethod == "GET" && request.httpBody == nil && !request.httpShouldHandleCookies)
            try expect(request.value(forHTTPHeaderField: "Authorization") == nil && request.value(forHTTPHeaderField: "Cookie") == nil)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try expect(value.feed.records.count == 1)
        for code in [403, 429, 500] {
            do {
                _ = try await ResetRadarClient.fetch { request in
                    (data, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
                }
                throw TestFailure(description: "Non-200 feed accepted")
            } catch let error as ResetRadarError {
                try expect(error.localizedDescription == ResetRadarError.unavailable.localizedDescription)
            }
        }
        do {
            _ = try await ResetRadarClient.fetch { _ in
                (data, HTTPURLResponse(url: URL(string: "https://example.com/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            throw TestFailure(description: "Redirect accepted")
        } catch is ResetRadarError {}
    }
}

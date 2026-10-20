import Foundation
import JavaScriptCore
import PaceCore

struct ClaudeWebTests {
    let org = "11111111-1111-4111-8111-111111111111"
    let other = "22222222-2222-4222-8222-222222222222"

    func testWebIdentityAndMissingFields() throws {
        let json = """
        {"status":200,"organizations":[{"uuid":"\(org)","name":"Personal"}],"organization":"\(org)",
         "usage":{"seven_day":{"utilization":25,"resets_at":"2026-10-17T01:00:00Z"}}}
        """
        let reply = try JSONDecoder().decode(ClaudeWebReply.self, from: Data(json.utf8))
        let snapshot = try reply.snapshot()
        try expect(snapshot.response.windows[0].window.remaining == 75)
        try expect(snapshot.accountKey.count == 64 && snapshot.accountKey != org)
        let unknown = json.replacingOccurrences(of: "\"organization\":\"\(org)\"", with: "\"organization\":\"\(other)\"")
        try expectThrows { try JSONDecoder().decode(ClaudeWebReply.self, from: Data(unknown.utf8)).snapshot() }
        for status in [401, 403, 409, 429, 500] {
            try expectThrows { try JSONDecoder().decode(ClaudeWebReply.self, from: Data("{\"status\":\(status)}".utf8)).snapshot() }
        }
    }

    func testOriginValidation() throws {
        try expect(ClaudeWebAPI.isClaudeOrigin(URL(string: "https://claude.ai/settings/usage")))
        for url in ["http://claude.ai", "https://claude.ai.evil.test", "https://evil.test/claude.ai", "https://claude.ai:8443", "file:///claude.ai"] {
            try expect(!ClaudeWebAPI.isClaudeOrigin(URL(string: url)))
        }
    }

    // Execute the actual WebKit bridge against a synthetic same-origin server.
    // This checks its requests and output, not a second copy of its logic.
    func runScript(responses: String, selected: String = "", origin: String = "https://claude.ai") throws -> [String: Any] {
        let context = try require(JSContext())
        var scriptError: String?
        context.exceptionHandler = { _, error in scriptError = error?.toString() }
        context.evaluateScript("""
        var location = {origin:'\(origin)'};
        var selectedOrganization = '\(selected)';
        var fixtures = \(responses), requests = [], output;
        function setTimeout() { return 1; } function clearTimeout() {}
        class AbortController { constructor(){this.signal={}} abort(){} }
        async function fetch(path, options) {
            requests.push({path,options});
            var fixture = fixtures.shift();
            if (!fixture) throw Error('Unexpected request');
            return {ok:fixture.status === 200, status:fixture.status,
                headers:{get:key => key === 'Content-Type' ? (fixture.type || 'application/json') : (fixture.retry || null)},
                text:async () => JSON.stringify(fixture.data)};
        }
        (async () => { \(ClaudeWebAPI.script) })().then(value => {output=JSON.parse(value)});
        """)
        let deadline = Date().addingTimeInterval(2)
        while context.objectForKeyedSubscript("output").isUndefined && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        try expect(scriptError == nil)
        let result = try require(context.objectForKeyedSubscript("output").toDictionary() as? [String: Any])
        let requests = try require(context.objectForKeyedSubscript("requests").toArray() as? [[String: Any]])
        for request in requests {
            let options = try require(request["options"] as? [String: Any])
            try expect(options["method"] as? String == "GET")
            try expect(options["redirect"] as? String == "error")
            try expect(options["credentials"] as? String == "same-origin")
        }
        return result.merging(["requests": requests]) { _, new in new }
    }

    func testBridgeOnlyReturnsUsageAndRequiresOrganizationChoice() throws {
        let orgs = #"{"status":200,"data":[{"uuid":"\#(org)","name":"Personal","private":"not returned"}]}"#
        let usage = #"{"status":200,"data":{"seven_day":{"utilization":12,"resets_at":"2026-10-17T01:00:00Z","private":"not returned"},"secret":"not returned"}}"#
        let result = try runScript(responses: "[\(orgs),\(usage)]")
        try expect(result["status"] as? Int == 200)
        let requests = try require(result["requests"] as? [[String: Any]])
        try expect(requests.count == 2)
        try expect(requests[1]["path"] as? String == "/api/organizations/\(org)/usage")
        let json = String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        try expect(!json.contains("not returned"))
        let switched = try runScript(responses: "[\(orgs)]", selected: other)
        try expect(switched["status"] as? Int == 409)
        try expect((switched["requests"] as? [Any])?.count == 1)
        let multiple = orgs.replacingOccurrences(of: "]}", with: ",{\"uuid\":\"\(other)\",\"name\":\"Team\"}]}")
        try expect(try runScript(responses: "[\(multiple)]")["status"] as? Int == 409)
        try expect(try runScript(responses: "[\(multiple),\(usage)]", selected: other)["organization"] as? String == other)
    }

    func testBridgeAuthExpiryChallengeAndRateLimit() throws {
        for status in [401, 403, 429, 503] {
            let result = try runScript(responses: "[{\"status\":\(status),\"retry\":\"900\"}]")
            try expect(result["status"] as? Int == status)
            try expect((result["requests"] as? [Any])?.count == 1)
        }
        try expect(try runScript(responses: #"[{"status":200,"type":"text/html","data":"login"}]"#)["status"] as? Int == 401)
        let foreign = try runScript(responses: "[]", origin: "https://accounts.google.com")
        try expect(foreign["status"] as? Int == 401)
        try expect((foreign["requests"] as? [Any])?.isEmpty == true)
    }

    func testBridgeIncludesFableWithoutLeakingOtherFields() throws {
        let orgs = #"{"status":200,"data":[{"uuid":"\#(org)","name":"Personal"}]}"#
        let usage = #"{"status":200,"data":{"seven_day":{"utilization":20,"resets_at":"2026-10-24T01:00:00Z"},"limits":[{"kind":"weekly_scoped","percent":42.5,"resets_at":"2026-10-23T03:00:00Z","scope":{"model":{"display_name":"Fable"}},"private":"must not cross bridge"}],"account_secret":"must not cross bridge"}}"#
        var result = try runScript(responses: "[\(orgs),\(usage)]")
        result.removeValue(forKey: "requests")
        let data = try JSONSerialization.data(withJSONObject: result)
        try expect(!String(decoding: data, as: UTF8.self).contains("must not cross bridge"))
        let snapshot = try JSONDecoder().decode(ClaudeWebReply.self, from: data).snapshot()
        let fable = try require(snapshot.response.windows.first { $0.bucketID == "claude_fable" })
        try expect(fable.window.usedPercent == 42.5 && fable.window.remaining == 57.5)
        let malformed = usage.replacingOccurrences(of: "42.5", with: "\"bad\"")
        let invalid = try runScript(responses: "[\(orgs),\(malformed)]")
        try expect((invalid["usage"] as? [String: Any])?["seven_day_fable"] == nil)
    }

    func testFableScopeZeroMissingAndAmbiguousRows() throws {
        func windows(_ rows: String) throws -> [String: Any] {
            let orgs = #"{"status":200,"data":[{"uuid":"\#(org)","name":"Personal"}]}"#
            let usage = #"{"status":200,"data":{"seven_day":{"utilization":20},"limits":\#(rows),"harbor_lantern":{"utilization":99}}}"#
            return try require(runScript(responses: "[\(orgs),\(usage)]")["usage"] as? [String: Any])
        }
        let row = #"{"kind":"weekly_scoped","percent":0,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}}"#
        let zero = try require(windows("[\(row)]")["seven_day_fable"] as? [String: Any])
        try expect(zero["utilization"] as? Double == 0 && zero["resets_at"] is NSNull)
        for rows in ["null", "[]", "[\(row),\(row)]", "[\(row.replacingOccurrences(of: "weekly_scoped", with: "weekly_all"))]",
                     "[\(row.replacingOccurrences(of: "Fable", with: "Other"))]", "[\(row.replacingOccurrences(of: "\"percent\":0", with: "\"percent\":-1"))]"] {
            let values = try windows(rows)
            try expect(values["seven_day_fable"] == nil)
            try expect(values["seven_day"] != nil)
        }
    }
}

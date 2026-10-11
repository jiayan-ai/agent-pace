import Foundation
import PaceCore

struct ClientTests {
    func testReadOnlyHandshakeAndResponseDecoding() throws {
        let script = #"""
        #!/usr/bin/python3
        import sys,json
        def receive(method):
            v=json.loads(sys.stdin.readline())
            assert v['method']==method
            return v
        def send(v):
            print(json.dumps(v),flush=True)
        receive('initialize')
        send({'id':1,'result':{}})
        receive('initialized')
        receive('account/read')
        send({'id':2,'result':{'account':{'type':'chatgpt','id':'fixture-account'}}})
        receive('account/rateLimits/read')
        send({'id':3,'result':{'rateLimits':{'limitId':'codex','primary':{'usedPercent':25,'windowDurationMins':10080,'resetsAt':2000000000}}}})
        sys.stdin.read()
        """#
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        defer { try? FileManager.default.removeItem(at: path) }
        let snapshot = try CodexClient.fetch(executable: path, timeout: 5)
        try expect((snapshot.response.windows.first?.window.remaining) == (75))
        try expect((snapshot.accountKey.count) == (64))
        try expect((snapshot.accountKey) != ("fixture-account"))
    }

    func testTimeoutIsBounded() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "#!/usr/bin/python3\nimport time\ntime.sleep(10)\n".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        defer { try? FileManager.default.removeItem(at: path) }
        let start = Date()
        try expectThrows { try CodexClient.fetch(executable: path, timeout: 0.2) }
        try expect((Date().timeIntervalSince(start)) < (3))
    }
}

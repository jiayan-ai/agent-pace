import Foundation
import Security
@testable import PaceCore

struct KeychainTests {
    func testBackgroundAccessDisablesUIAndRestoresState() throws {
        var allowed = true
        let value = try KeychainInteraction.perform(allowPrompt: false, get: { state in
            state.pointee = DarwinBoolean(allowed); return errSecSuccess
        }, set: { state in
            allowed = state; return errSecSuccess
        }, operation: {
            try expect(!allowed)
            return "fixture"
        })
        try expect(value == "fixture")
        try expect(allowed)
    }

    func testDeniedAccessRestoresStateAndFailedGuardSkipsRead() throws {
        var allowed = true
        try expectThrows {
            try KeychainInteraction.perform(allowPrompt: false, get: { state in
                state.pointee = DarwinBoolean(allowed); return errSecSuccess
            }, set: { state in
                allowed = state; return errSecSuccess
            }, operation: {
                try expect(!allowed)
                throw ClaudeUsageError.keychainPermission
            })
        }
        try expect(allowed)
        var readCalled = false
        try expectThrows {
            try KeychainInteraction.perform(allowPrompt: false, get: { state in
                state.pointee = true; return errSecSuccess
            }, set: { _ in errSecInteractionNotAllowed }, operation: {
                readCalled = true
            })
        }
        try expect(!readCalled)
    }

    func testExplicitConnectionCanAskAndRestoresDisabledState() throws {
        var allowed = false
        try KeychainInteraction.perform(allowPrompt: true, get: { state in
            state.pointee = DarwinBoolean(allowed); return errSecSuccess
        }, set: { state in
            allowed = state; return errSecSuccess
        }, operation: { try expect(allowed) })
        try expect(!allowed)
    }
}

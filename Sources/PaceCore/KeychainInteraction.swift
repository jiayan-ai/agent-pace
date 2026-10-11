import Foundation
import Security

/// Classic login-keychain ACL prompts can ignore LAContext.interactionNotAllowed.
/// Serialize the process-wide legacy UI flag, restore it on every exit path, and
/// fail closed if a silent read cannot be enforced. This does not grant access.
enum KeychainInteraction {
    private static let lock = NSLock()

    static func perform<T>(allowPrompt: Bool,
                           get: (UnsafeMutablePointer<DarwinBoolean>) -> OSStatus = SecKeychainGetUserInteractionAllowed,
                           set: (Bool) -> OSStatus = SecKeychainSetUserInteractionAllowed,
                           operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        var previous: DarwinBoolean = false
        guard get(&previous) == errSecSuccess,
              set(allowPrompt) == errSecSuccess else {
            throw ClaudeUsageError.keychainPermission
        }
        defer { _ = set(previous.boolValue) }
        return try operation()
    }
}

import Foundation
import Security
import CommonCrypto
import LocalAuthentication

/// Only the desktop app's own encrypted OAuth cache is read. No cookies,
/// browser profiles, refresh tokens, or credentials are written or exported.
public enum ClaudeDesktopLogin {
    public struct Credential {
        let token: String
        public let account: String
        public let organization: String
    }

    public static func read(allowPrompt: Bool = false) throws -> Credential {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/config.json")
        guard let data = try? Data(contentsOf: url), data.count < 5_000_000,
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = config["lastKnownAccountUuid"] as? String, !account.isEmpty else {
            throw ClaudeUsageError.notSignedIn
        }
        // New desktop versions scope credentials by account; prefer V2 and do
        // not fall back to a retired V1 token when a V2 cache exists.
        guard let encoded = (config["oauth:tokenCacheV2"] ?? config["oauth:tokenCache"]) as? String,
              let encrypted = Data(base64Encoded: encoded) else { throw ClaudeUsageError.notSignedIn }
        let password = try safeStoragePassword(allowPrompt: allowPrompt)
        let plain = try decrypt(encrypted, password: password)
        return try credential(from: plain, account: account)
    }

    public static func credential(from data: Data, account: String, now: Date = Date()) throws -> Credential {
        struct Entry: Decodable { let token: String; let expiresAt: Double }
        guard let entries = try? JSONDecoder().decode([String: Entry?].self, from: data) else {
            throw ClaudeUsageError.invalidResponse
        }
        var candidates: [(Credential, Double)] = []
        var hadExpired = false
        for (key, entry) in entries {
            guard let entry, key.lowercased().hasPrefix("acct:\(account.lowercased())|"),
                  let separator = key.firstIndex(of: "|") else { continue }
            let components = String(key[key.index(after: separator)...]).components(separatedBy: ":https://api.anthropic.com:")
            guard components.count == 2 else { continue }
            let scopes = components[1].split(separator: " ")
            guard scopes.contains("user:profile"), scopes.contains("user:inference") else { continue }
            let identity = components[0].split(separator: ":")
            guard identity.count == 2, UUID(uuidString: String(identity[1])) != nil,
                  !entry.token.isEmpty, entry.expiresAt.isFinite else { continue }
            guard entry.expiresAt / 1000 > now.timeIntervalSince1970 else { hadExpired = true; continue }
            candidates.append((Credential(token: entry.token, account: account, organization: String(identity[1])), entry.expiresAt))
        }
        // Never guess which subscription to use when several organizations are
        // cached. The user can select the desired account in Claude first.
        guard Set(candidates.map { $0.0.organization }).count <= 1 else { throw ClaudeUsageError.ambiguousAccount }
        guard let candidate = candidates.max(by: { $0.1 < $1.1 }) else {
            throw hadExpired ? ClaudeUsageError.expired : ClaudeUsageError.notSignedIn
        }
        return candidate.0
    }

    private static func safeStoragePassword(allowPrompt: Bool) throws -> Data {
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = try KeychainInteraction.perform(allowPrompt: allowPrompt) {
            SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess, let data = result as? Data, !data.isEmpty else {
            throw ClaudeUsageError.keychainPermission
        }
        return data
    }

    public static func decrypt(_ data: Data, password: Data) throws -> Data {
        // Electron/Chromium macOS v10 safeStorage: PBKDF2-SHA1, 1003 rounds,
        // AES-128-CBC, PKCS#7. Reject unknown formats rather than guessing.
        guard data.starts(with: Data("v10".utf8)), data.count > 3,
              (data.count - 3) % kCCBlockSizeAES128 == 0 else { throw ClaudeUsageError.invalidResponse }
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        defer { _ = key.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let salt = Array("saltysalt".utf8)
        let derivation = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.bindMemory(to: Int8.self).baseAddress,
                                password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                                1003, &key, key.count)
        }
        guard derivation == kCCSuccess else { throw ClaudeUsageError.invalidResponse }
        let cipher = Data(data.dropFirst(3)), iv = [UInt8](repeating: 32, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        let capacity = output.count
        var length = 0
        let status = cipher.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    key, key.count, iv, bytes.baseAddress, cipher.count, &output, capacity, &length)
        }
        guard status == kCCSuccess else { throw ClaudeUsageError.invalidResponse }
        return Data(output.prefix(length))
    }
}

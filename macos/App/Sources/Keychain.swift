// Secrets in the login keychain.
//
// Omarchy keeps these in gnome-keyring through secret-tool; the Mac has the
// Keychain, reached through SecItem. Nothing secret is ever written to a file,
// a log or a snapshot.

import Foundation
import Security

enum Keychain {
    /// The OAuth client, as downloaded from Google. Stored under "default",
    /// because one client serves every account.
    static let googleClient = "google-client"
    /// One refresh token per Google account.
    static let googleToken = "google-token"

    private static let service = "crossroads"

    static func get(_ kind: String, account: String) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(kind, account, returning: true) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func put(_ kind: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        let found = query(kind, account, returning: false)

        // Replace what is there rather than adding a second copy.
        let update = SecItemUpdate(found as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return }

        var item = found
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func remove(_ kind: String, account: String) {
        SecItemDelete(query(kind, account, returning: false) as CFDictionary)
    }

    private static func query(_ kind: String, _ account: String, returning: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            // The kind is part of the account, so one service can hold the
            // client and a token per address without them colliding.
            kSecAttrAccount: "\(kind):\(account)",
        ]
        if returning {
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
        }
        return query
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Keychain: \(message)"
    }
}

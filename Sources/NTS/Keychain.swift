import Foundation
import Security

/// One secret in the login keychain. Reading can put a system prompt on screen and waits for it, so stay off the main thread.
enum Keychain {
    enum Answer: Equatable {
        case value(String)
        case missing
        /// It may well be there, but could not be read just now, as with a locked keychain.
        case unreadable
    }

    static func read(_ name: String) -> Answer {
        var query = item(name)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }.map(Answer.value) ?? .missing
        // Saying no to the system prompt counts as gone too: asking again on every refresh would only nag.
        case errSecItemNotFound, errSecAuthFailed, errSecUserCanceled:
            return .missing
        default:
            return .unreadable
        }
    }

    static func write(_ value: String, as name: String) {
        // A fresh item belongs to this build. An update would keep the item of an older build, and macOS asks again for that one.
        delete(name)
        var query = item(name)
        query[kSecValueData] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ name: String) {
        SecItemDelete(item(name) as CFDictionary)
    }

    private static func item(_ name: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "nl.sanderjanssen.nts", kSecAttrAccount: name]
    }
}

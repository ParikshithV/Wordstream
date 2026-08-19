//
//  Keychain.swift
//  Wordstream
//

import Foundation
import Security

/// API keys live here, never in UserDefaults.
///
/// UserDefaults is a plist in the app's container — readable by anything running
/// as the user, backed up in plain text, and trivially dumped with `defaults read`.
/// A cloud API key is a billable credential; it belongs in the Keychain.
enum Keychain {
    private static let service = "app.wordstream.apikeys"

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }

        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Existence without decryption.
    ///
    /// This used to call `get`, which meant every dictation decrypted the API
    /// key just to ask whether one had been saved — `EnhancementPipeline.resolve`
    /// reaches it through `isAvailable`, on the path the user is waiting behind.
    /// Testing for the item alone answers the same question. The old version also
    /// rejected an empty value, which `set` refuses to store in the first place.
    static func has(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

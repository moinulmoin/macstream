import Foundation
import LocalAuthentication
import Security

enum MacStreamDestinationKeychain {
    private static let service = "com.ideaplexa.macstream.destination"
    private static let account = "rtmp-url"

    static func loadRTMPURL(allowUserInteraction: Bool = false) -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowUserInteraction {
            query[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }

    @discardableResult
    static func saveRTMPURL(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return deleteRTMPURL()
        }

        let data = Data(trimmedValue.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = baseQuery()
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteRTMPURL(allowUserInteraction: Bool = false) -> Bool {
        var query = baseQuery()
        if !allowUserInteraction {
            query[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        }

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func nonInteractiveAuthenticationContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}

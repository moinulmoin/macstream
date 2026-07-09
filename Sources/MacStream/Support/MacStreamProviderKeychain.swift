import Foundation
import LocalAuthentication
import Security

enum MacStreamProviderKeychain {
    private static let service = "com.ideaplexa.macstream.provider"
    private static let openAICompatibleAPIKeyAccount = "openai-compatible-api-key"

    static func loadOpenAICompatibleAPIKey(allowUserInteraction: Bool = false) -> String? {
        var query = baseQuery(account: openAICompatibleAPIKeyAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowUserInteraction {
            query[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }

    @discardableResult
    static func saveOpenAICompatibleAPIKey(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return deleteOpenAICompatibleAPIKey()
        }

        let data = Data(trimmedValue.utf8)
        let query = baseQuery(account: openAICompatibleAPIKeyAccount)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteOpenAICompatibleAPIKey() -> Bool {
        let status = SecItemDelete(baseQuery(account: openAICompatibleAPIKeyAccount) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String) -> [String: Any] {
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

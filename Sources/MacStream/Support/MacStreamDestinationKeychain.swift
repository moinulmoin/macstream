import Foundation
import LocalAuthentication
import MacStreamCore
import Security

enum MacStreamDestinationKeychain {
    private static let service = "com.ideaplexa.macstream.destination"
    private static let streamKeyAccountPrefix = "destination-stream-key"

    static func loadRTMPStreamKey(for destinationID: UUID, allowUserInteraction: Bool = false) -> String? {
        guard allowUserInteraction else { return nil }

        var query = baseQuery(destinationID: destinationID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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

    static func loadRTMPURL(
        for destinationID: UUID,
        serverURL: String,
        allowUserInteraction: Bool = false
    ) -> String? {
        guard let streamKey = loadRTMPStreamKey(
            for: destinationID,
            allowUserInteraction: allowUserInteraction
        ) else {
            return nil
        }

        return StreamDestination.combinedRTMPURL(serverURL: serverURL, streamKey: streamKey)
    }

    @discardableResult
    static func saveRTMPStreamKey(_ value: String, for destinationID: UUID) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return deleteRTMPStreamKey(for: destinationID)
        }

        let data = Data(trimmedValue.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(destinationID: destinationID) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }

        var item = baseQuery(destinationID: destinationID)
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteRTMPStreamKey(for destinationID: UUID, allowUserInteraction: Bool = false) -> Bool {
        var query = baseQuery(destinationID: destinationID)
        if !allowUserInteraction {
            query[kSecUseAuthenticationContext as String] = nonInteractiveAuthenticationContext()
        }

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(destinationID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: destinationID)
        ]
    }

    private static func account(for destinationID: UUID) -> String {
        "\(streamKeyAccountPrefix).\(destinationID.uuidString)"
    }

    private static func nonInteractiveAuthenticationContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}

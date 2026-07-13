import Foundation
import Security

protocol ClientKeyStorage {
    func read() -> String
    @discardableResult func save(_ value: String) -> Bool
    func clear()
}

final class KeychainClientKeyStorage: ClientKeyStorage {
    private let service: String
    private let account: String

    init(service: String = "local.codex.lgvolume", account: String = "webos-client-key") {
        self.service = service
        self.account = account
    }

    func read() -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    @discardableResult func save(_ value: String) -> Bool {
        if value.isEmpty {
            clear()
            return true
        }

        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var item = baseQuery()
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

import Foundation
import Security

public protocol CredentialStoring: Sendable {
    func save(_ value: String, account: String) throws
    func value(account: String) throws -> String?
    func remove(account: String) throws
}

public enum CredentialStoreError: LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "Keychain returned status \(status)."
        case .invalidData:
            "The credential stored in Keychain is unreadable."
        }
    }
}

public struct KeychainCredentialStore: CredentialStoring {
    private let service: String

    public init(service: String = "com.jashdubal.Atten.providers") {
        self.service = service
    }

    public func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData] = data
            newItem[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    public func value(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidData
        }
        return value
    }

    public func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}

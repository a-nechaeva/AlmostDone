import CryptoKit
import Foundation
import Security

struct KeychainSessionStorage: SessionStorage {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func load() throws -> StoredSession? {
        let marker = try removalMarker()
        if FileManager.default.fileExists(atPath: marker.path) {
            try deleteItem()
            try? FileManager.default.removeItem(at: marker)
            return nil
        }

        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
            let session = try? JSONDecoder().decode(StoredSession.self, from: data)
        else { throw SessionError.storageUnavailable }
        return session
    }

    func save(_ session: StoredSession) throws {
        let marker = try removalMarker()
        guard !FileManager.default.fileExists(atPath: marker.path) else {
            throw SessionError.storageUnavailable
        }
        let data = try JSONEncoder().encode(session)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(item as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SessionError.storageUnavailable }

        var record = item
        record[kSecValueData as String] = data
        record[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(record as CFDictionary, nil) == errSecSuccess else {
            throw SessionError.storageUnavailable
        }
    }

    func remove() throws {
        // Keep an empty marker until Keychain confirms deletion. A restart after a
        // failed deletion must try cleanup before reading the old credentials.
        let marker = try? removalMarker()
        if let marker { try? Data().write(to: marker, options: .atomic) }
        try deleteItem()
        if let marker { try? FileManager.default.removeItem(at: marker) }
    }

    private func deleteItem() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionError.storageUnavailable
        }
    }

    private func removalMarker() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let namespace = SHA256.hash(data: Data("\(service)|\(account)".utf8))
        let filename = namespace.map { String(format: "%02x", $0) }.joined()
        return support.appending(path: "session-logout-\(filename)")
    }

    private var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

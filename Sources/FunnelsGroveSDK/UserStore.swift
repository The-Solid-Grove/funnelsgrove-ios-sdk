import Foundation
import os
import Security

private let keychainLogger = Logger(subsystem: "com.funnelsgrove.sdk", category: "Keychain")

protocol UserStore {
    func read() -> LinkedUser?
    func save(_ user: LinkedUser) throws
    func delete()
}

struct KeychainError: Error, Equatable, CustomStringConvertible {
    let status: OSStatus

    var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Keeps the linked user's ID and email in one keychain item, so they always change together, and lets iCloud
/// Keychain sync it. Keychain items outlive app deletion in practice; Apple does not guarantee it.
struct KeychainUserStore: UserStore {
    var service = "com.funnelsgrove.sdk"
    var account = "user"

    func read() -> LinkedUser? {
        var query = baseQuery()
        // Without SynchronizableAny the query skips iCloud-synced items.
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            log(status, action: "Reading the user")
            return nil
        }
        guard let user = Self.decode(data) else {
            keychainLogger.error("The stored user is unreadable: treating it as no user")
            return nil
        }
        return user
    }

    func save(_ user: LinkedUser) throws {
        // Rewriting an unchanged user would only churn iCloud Keychain sync.
        if read() == user { return }
        // Delete first so the add never hits errSecDuplicateItem, whatever the old item's sync state.
        delete()
        var attributes = baseQuery()
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = try Self.encode(user)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete() {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        log(SecItemDelete(query as CFDictionary), action: "Deleting the user")
    }

    static func encode(_ user: LinkedUser) throws -> Data {
        try JSONEncoder().encode(user)
    }

    /// The stored user, or `nil` for data that is not one: a damaged item must not turn into a user ID. The ID and
    /// the email pass the same checks as in a link, so tightening the ID check drops users stored under the old one.
    static func decode(_ data: Data) -> LinkedUser? {
        guard let user = try? JSONDecoder().decode(LinkedUser.self, from: data),
              LinkParser.isValidUserId(user.userId)
        else {
            return nil
        }
        return LinkedUser(userId: user.userId, email: LinkParser.validEmail(user.email))
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func log(_ status: OSStatus, action: String) {
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        keychainLogger.error("\(action, privacy: .public) failed: \(KeychainError(status: status).description, privacy: .public)")
    }
}

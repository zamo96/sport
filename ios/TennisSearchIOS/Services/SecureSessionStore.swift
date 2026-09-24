import Foundation
import Security

/// Shared by the app and widget. Credentials never leave the device via backups.
struct SecureSessionStore {
    private static let legacyTokenKey = "SportSearch.sessionToken"
    private static let appGroupIdentifier = "group.shop.sportsearch.app"
    private let query: [String: Any]

    init(baseURL: URL) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "shop.sportsearch.session.\(Self.origin(for: baseURL))",
            kSecAttrAccount as String: "sessionToken"
        ]
        if let group = Bundle.main.object(forInfoDictionaryKey: "SessionKeychainAccessGroup") as? String,
           !group.isEmpty, !group.contains("$(") {
            query[kSecAttrAccessGroup as String] = group
        }
        self.query = query
    }

    static func origin(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "https"
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(url.host?.lowercased() ?? ""):\(port)"
    }

    func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    func write(_ token: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.unavailable }
        Self.removeLegacyTokens()
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
        Self.removeLegacyTokens()
    }

    /// Legacy preferences had no origin binding. Migrate only to the production
    /// origin they were issued for; a local/debug server must never receive them.
    func migrateLegacyToken(baseURL: URL) -> String? {
        if let token = read() {
            Self.removeLegacyTokens()
            return token
        }
        defer { Self.removeLegacyTokens() }
        guard Self.origin(for: baseURL) == "https://sportsearch.shop:443",
              let token = UserDefaults.standard.string(forKey: Self.legacyTokenKey)
                ?? UserDefaults(suiteName: Self.appGroupIdentifier)?.string(forKey: Self.legacyTokenKey),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (try? write(token)) != nil else { return nil }
        return token
    }

    private static func removeLegacyTokens() {
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults(suiteName: appGroupIdentifier)?.removeObject(forKey: legacyTokenKey)
    }

    private enum StorageError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Не удалось безопасно сохранить вход. Попробуй войти ещё раз." }
    }
}

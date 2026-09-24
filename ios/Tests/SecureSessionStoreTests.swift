import Foundation
import Security

@main
struct SecureSessionStoreTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }
    static func main() throws {
        // A unique origin keeps this runtime test isolated from real credentials.
        let host = "session-test-\(UUID().uuidString.lowercased()).invalid"
        let url = URL(string: "https://\(host)")!
        let store = SecureSessionStore(baseURL: url)
        defer { store.clear() }
        expect(store.read() == nil, "New installation has no stored token")
        try store.write("first-fixture-token")
        expect(store.read() == "first-fixture-token", "Keychain roundtrip")
        expect(SecureSessionStore(baseURL: URL(string: "https://\(host):443/api")!).read() == "first-fixture-token", "Equivalent origin shares token")
        expect(SecureSessionStore(baseURL: URL(string: "http://\(host)")!).read() == nil, "Scheme isolation")
        expect(SecureSessionStore(baseURL: URL(string: "https://\(host):8443")!).read() == nil, "Port isolation")
        expect(SecureSessionStore(baseURL: URL(string: "https://other-\(host)")!).read() == nil, "Host isolation")
        try store.write("replacement-fixture-token")
        expect(store.read() == "replacement-fixture-token", "Existing item updates without duplicates")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "shop.sportsearch.session.\(SecureSessionStore.origin(for: url))",
            kSecAttrAccount as String: "sessionToken",
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, "Read item protection metadata")
        let attributes = result as? [String: Any]
        if let protection = attributes?[kSecAttrAccessible as String] as? String {
            expect(protection == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String, "Device-only after-first-unlock protection")
        } else {
            print("Protection metadata unavailable in the macOS login Keychain; device protection needs a signed iOS run")
        }
        store.clear()
        expect(store.read() == nil, "Logout deletes stored token")
        print("Secure session store: \(assertions) runtime assertions passed")
    }
}

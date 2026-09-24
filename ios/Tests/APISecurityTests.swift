import Foundation

private final class StubURLProtocol: URLProtocol {
    static var handler: ((StubURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}
    func respond(_ body: String = "{\"ok\":true}", headers: [String: String] = [:], status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main
struct APISecurityTests {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError(message) }
    }
    struct OK: Decodable { let ok: Bool }

    static func main() async throws {
        let baseURL = URL(string: "https://api-security-test.invalid")!
        let cookie = HTTPCookie(properties: [.domain: "api-security-test.invalid", .path: "/", .name: "tennis_session", .value: "legacy-secret", .secure: "TRUE"])!
        HTTPCookieStorage.shared.setCookie(cookie)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let api = APIClient(baseURL: baseURL, sessionConfiguration: configuration)
        expect(!(HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).contains { $0.name == "tennis_session" }, "Legacy session cookie is removed")
        try api.setSessionToken("first-token", expectedGeneration: api.authenticationGeneration)

        StubURLProtocol.handler = { transport in
            expect(transport.request.value(forHTTPHeaderField: "Authorization") == "Bearer first-token", "Authenticated request uses bearer")
            expect(transport.request.value(forHTTPHeaderField: "Cookie") == nil, "No cookie authentication")
            transport.respond(headers: ["Set-Cookie": "tennis_session=unwanted; Path=/; Secure"])
        }
        let _: OK = try await api.request(path: "me")
        let _: OK = try await api.request(path: "me")
        expect(!(HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).contains { $0.name == "tennis_session" }, "Set-Cookie is not persisted")

        let oldAttempt = api.beginAuthenticationAttempt()
        let latestAttempt = api.beginAuthenticationAttempt()
        do {
            try api.setSessionToken("stale-token", expectedGeneration: oldAttempt)
            fatalError("Older authentication attempt won")
        } catch is CancellationError { assertions += 1 }
        try api.setSessionToken("second-token", expectedGeneration: latestAttempt)
        let preLogout = api.authenticationGeneration
        api.clearAuthSession()
        do {
            try api.setSessionToken("stale-token", expectedGeneration: preLogout)
            fatalError("Old authentication restored after logout")
        } catch is CancellationError { assertions += 1 }

        StubURLProtocol.handler = { transport in
            expect(transport.request.value(forHTTPHeaderField: "Authorization") == nil, "Guest request has no bearer after logout")
            expect(transport.request.value(forHTTPHeaderField: "Cookie") == nil, "Guest request has no cookie after logout")
            transport.respond()
        }
        let _: OK = try await api.request(path: "me")

        StubURLProtocol.handler = { $0.respond("{\"sessionToken\":\"PRIVATE_SECRET\",\"message\":\"private-chat\"}") }
        do {
            let _: OK = try await api.request(path: "private-data")
            fatalError("Malformed payload succeeded")
        } catch {
            expect(!error.localizedDescription.contains("PRIVATE_SECRET") && !error.localizedDescription.contains("private-chat"), "Errors do not disclose raw payload")
        }

        StubURLProtocol.handler = { $0.respond("{\"error\":\"Неверный код\",\"errorCode\":\"AUTH_INVALID_CODE\"}", status: 401) }
        do {
            let _: OK = try await api.request(path: "auth/verify", method: "POST")
            fatalError("Invalid OTP succeeded")
        } catch {
            expect(error.localizedDescription == "Неверный код", "Wrong OTP preserves actionable server message")
        }
        do {
            let _: OK = try await api.request(path: "me")
            fatalError("Expired session succeeded")
        } catch APIError.unauthorized { assertions += 1 }

        try api.setSessionToken("media-token", expectedGeneration: api.authenticationGeneration)
        StubURLProtocol.handler = { transport in
            let expected = transport.request.url?.host == baseURL.host ? "Bearer media-token" : nil
            expect(transport.request.value(forHTTPHeaderField: "Authorization") == expected, "Media credentials stay on API origin")
            transport.respond()
        }
        _ = try await api.download(path: "https://api-security-test.invalid/media/image")
        _ = try await api.download(path: "https://cdn-security-test.invalid/image")

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: baseURL)
        let redirectResponse = HTTPURLResponse(url: baseURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        api.urlSession(session, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: URLRequest(url: URL(string: "https://other-security-test.invalid")!)) { request in
            expect(request == nil, "Cross-origin auth redirect blocked")
        }
        api.urlSession(session, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: URLRequest(url: URL(string: "http://api-security-test.invalid")!)) { request in
            expect(request == nil, "HTTPS downgrade redirect blocked")
        }
        api.urlSession(session, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: URLRequest(url: baseURL.appendingPathComponent("next"))) { request in
            expect(request != nil, "Same-origin redirect allowed")
        }

        let requestStarted = AsyncStream<StubURLProtocol>.makeStream()
        StubURLProtocol.handler = { requestStarted.continuation.yield($0) }
        let slowRequest = Task { () throws -> OK in try await api.request(path: "slow-profile") }
        var iterator = requestStarted.stream.makeAsyncIterator()
        let transport = await iterator.next()!
        api.clearAuthSession()
        transport.respond()
        do {
            _ = try await slowRequest.value
            fatalError("In-flight old-account response survived logout")
        } catch is CancellationError { assertions += 1 }
        requestStarted.continuation.finish()

        try api.setSessionToken("logout-token", expectedGeneration: api.authenticationGeneration)
        let logoutStarted = AsyncStream<StubURLProtocol>.makeStream()
        StubURLProtocol.handler = { logoutStarted.continuation.yield($0) }
        api.logout(pushDeviceToken: "push-test-token")
        var logoutIterator = logoutStarted.stream.makeAsyncIterator()
        let logoutTransport = await logoutIterator.next()!
        expect(logoutTransport.request.value(forHTTPHeaderField: "Authorization") == "Bearer logout-token", "Logout captures the old credential")
        try api.setSessionToken("next-account-token", expectedGeneration: api.authenticationGeneration)
        logoutTransport.respond()
        try await api.waitForLogoutCleanup()
        logoutStarted.continuation.finish()
        StubURLProtocol.handler = { transport in
            expect(transport.request.value(forHTTPHeaderField: "Authorization") == "Bearer next-account-token", "Delayed logout does not clear subsequent login")
            transport.respond()
        }
        let _: OK = try await api.request(path: "me")
        print("API security: \(assertions) assertions passed")
    }
}

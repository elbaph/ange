import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {
    func data(_ json: String) -> Data { Data(json.utf8) }

    func testLegacyClaudeDecimalAndDateFormats() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":42.5,"resets_at":"2026-09-07T12:00:00Z"},
         "seven_day":{"utilization":0,"resets_at":"2026-09-08T12:00:00.123Z"},
         "seven_day_overage_included":{"utilization":81.2,"resets_at":1788825600}}
        """))
        XCTAssertEqual(result.metrics.map(\.percent), [42.5, 0, 81.2])
        XCTAssertTrue(result.metrics.allSatisfy { $0.resetsAt != nil })
        XCTAssertEqual(result.metrics.last?.title, "Fable · Weekly")
    }

    func testScopedFablePreferredAndOtherScopesIgnored() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":12}, "seven_day_overage_included":{"utilization":88},
         "limits":[
          {"kind":"spend","percent":98},
          {"kind":"weekly_scoped","percent":70,"scope":{"model":{"display_name":"Opus"}}},
          {"kind":"weekly_scoped","percent":0,"resets_at":"2026-09-07T12:00:00Z",
           "scope":{"model":{"display_name":"Fable 5.1"}}}]}
        """))
        XCTAssertEqual(result.metrics.last?.percent, 0)
        XCTAssertNotNil(result.metrics.last?.resetsAt)
    }

    func testMissingFableAndWeeklyAreUnknownNotZero() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":0}, "seven_day":null, "limits":null}
        """))
        XCTAssertEqual(result.metrics.first?.percentageText, "0%")
        XCTAssertNil(result.metrics[1].percent)
        XCTAssertEqual(result.metrics[2].percentageText, "—")
        XCTAssertThrowsError(try UsageParser.claude(data("{}")))
    }

    func testMalformedValuesDoNotBecomeZeroOrHideOtherWindows() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":false}, "seven_day":{"utilization":21},
         "seven_day_overage_included":{"utilization":"bad","resets_at":"bad"}}
        """))
        XCTAssertNil(result.metrics[0].percent)
        XCTAssertEqual(result.metrics[1].percent, 21)
        XCTAssertNil(result.metrics[2].resetsAt)
        XCTAssertEqual(UsageMetric(id: "x", title: "x", percent: 130, resetsAt: nil).fraction, 1)
        XCTAssertEqual(UsageMetric(id: "x", title: "x", percent: -10, resetsAt: nil).fraction, 0)
    }

    func testOldConfigMigrationPreservesUnknownFieldsAndSecuresFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        try data("{\"sessionKey\":\"old\",\"futureField\":42,\"codexAccessToken\":\"legacy\"}").write(to: url)
        var config = try WidgetConfig.load(from: url)
        XCTAssertEqual(config.sessionKey, "old")
        config.sessionKey = nil
        config.claudeEnabled = false
        try config.save(to: url)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertNil(saved["sessionKey"])
        XCTAssertNil(saved["codexAccessToken"])
        XCTAssertEqual(saved["futureField"] as? Int, 42)
        XCTAssertEqual(try WidgetConfig.load(from: url).claudeEnabled, false)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testInvalidConfigIsNotSilentlyOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data("invalid json").write(to: url)
        XCTAssertThrowsError(try WidgetConfig.load(from: url))
        XCTAssertThrowsError(try WidgetConfig().save(to: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid json")
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
    }
    override func tearDown() { session.invalidateAndCancel(); StubProtocol.handler = nil }

    func testOAuthGoesToAnthropicOnly() async {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer claude-test")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (200, "{\"five_hour\":{\"utilization\":10}}")
        }
        let result = await UsageClient(session: session).fetch(config: WidgetConfig(oauthToken: "claude-test"))
        XCTAssertNil(result.claude.error)
        XCTAssertEqual(result.claude.metrics.first?.percent, 10)
    }

    func testOAuthFallsBackToSession() async {
        StubProtocol.handler = { request in
            if request.url?.host == "api.anthropic.com" { return (401, "{}") }
            XCTAssertEqual(request.url?.host, "claude.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=session-test")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, "{\"five_hour\":{\"utilization\":22.2}}")
        }
        let result = await UsageClient(session: session).fetch(config: WidgetConfig(
            sessionKey: "session-test", organizationId: "11111111-1111-1111-1111-111111111111",
            oauthToken: "expired-test"))
        XCTAssertNil(result.claude.error)
        XCTAssertEqual(result.claude.metrics.first?.percent, 22.2)
    }

    func testDisabledClaudeDoesNotFetch() async {
        StubProtocol.handler = { _ in XCTFail("Disabled provider must not fetch"); return (500, "{}") }
        let result = await UsageClient(session: session).fetch(config: WidgetConfig(
            oauthToken: "claude-test", claudeEnabled: false))
        XCTAssertFalse(result.claude.isEnabled)
    }

    func testRateLimitErrorAndInvalidOrganization() async {
        StubProtocol.handler = { _ in (429, "{}") }
        let client = UsageClient(session: session)
        let result = await client.fetchClaude(WidgetConfig(oauthToken: "test"))
        XCTAssertEqual(result.error, UsageError.http(429).localizedDescription)
        let invalid = await client.fetchClaude(WidgetConfig(sessionKey: "test", organizationId: "../wrong?query"))
        XCTAssertEqual(invalid.error, "Organization ID must be a UUID.")
    }
}

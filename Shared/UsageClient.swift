import Foundation

struct UsageClient {
    var session: URLSession = .shared

    func fetch(config: WidgetConfig) async -> UsageSnapshot {
        await UsageSnapshot(date: Date(), claude: fetchClaude(config))
    }

    private func get(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        guard response.statusCode == 200 else { throw UsageError.http(response.statusCode) }
        return data
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetchClaude(_ config: WidgetConfig) async -> ProviderUsage {
        guard config.claudeEnabled != false else { return ProviderUsage(name: "Claude", isEnabled: false) }
        var failure: Error = UsageError.missingClaude
        if let token = config.oauthToken?.nonempty {
            var req = request(URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            do { return try UsageParser.claude(await get(req)) } catch { failure = error }
        }
        if let key = config.sessionKey?.nonempty, let org = config.organizationId?.nonempty {
            // An organization is a UUID; never interpolate arbitrary path/query characters.
            guard UUID(uuidString: org) != nil else {
                return ProviderUsage(name: "Claude", error: "Organization ID must be a UUID.")
            }
            var req = request(URL(string: "https://claude.ai/api/organizations/\(org)/usage")!)
            req.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
            do { return try UsageParser.claude(await get(req)) } catch { failure = error }
        }
        return ProviderUsage(name: "Claude", error: failure.localizedDescription)
    }
}

extension String {
    var nonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

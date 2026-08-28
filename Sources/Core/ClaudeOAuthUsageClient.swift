import CryptoKit
import Foundation
import Security

enum ClaudeOAuthCredentialReader {
    static func readAccessToken(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> String {
        let configDirectory = environment["CLAUDE_CONFIG_DIR"].map(URL.init(fileURLWithPath:))
            ?? homeDirectory.appendingPathComponent(".claude", isDirectory: true)

        for service in serviceNames(configDirectory: configDirectory) {
            if let data = keychainData(service: service),
               let token = parseAccessToken(data) {
                return token
            }
        }

        let credentialsURL = configDirectory.appendingPathComponent(".credentials.json")
        if let data = try? Data(contentsOf: credentialsURL),
           let token = parseAccessToken(data) {
            return token
        }

        throw ProviderUsageClientError.credentialsMissing
    }

    static func parseAccessToken(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    static func serviceNames(configDirectory: URL) -> [String] {
        let digest = SHA256.hash(data: Data(configDirectory.path.utf8))
        let prefix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return ["Claude Code-credentials-\(prefix)", "Claude Code-credentials"]
    }

    private static func keychainData(service: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: NSUserName(),
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }
}

enum ClaudeOAuthUsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")

    static func request(accessToken: String) throws -> URLRequest {
        guard let endpoint else {
            throw ProviderUsageClientError.malformedResponse
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func fetch(accessToken: String) async throws -> SubscriptionUsage {
        let request = try request(accessToken: accessToken)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderUsageClientError.malformedResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderUsageClientError.httpStatus(httpResponse.statusCode)
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> SubscriptionUsage {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw ProviderUsageClientError.malformedResponse
        }

        let candidates: [(key: String, name: String)] = [
            ("five_hour", "5 hours"),
            ("seven_day", "7 days"),
        ]
        let windows = candidates.compactMap { candidate -> SubscriptionUsageWindow? in
            guard let raw = root[candidate.key] as? [String: Any] else { return nil }
            let percent = (raw["utilization"] as? NSNumber)?.doubleValue
                ?? (raw["used_percentage"] as? NSNumber)?.doubleValue
            guard let percent,
                  let resetDate = resetDate(raw["resets_at"]) else {
                return nil
            }
            return SubscriptionUsageWindow(
                name: candidate.name,
                usedPercent: min(100, max(0, percent)),
                resetsAt: resetDate
            )
        }

        guard let primary = windows.first else {
            throw ProviderUsageClientError.malformedResponse
        }
        return SubscriptionUsage(primary: primary, secondary: windows.dropFirst().first)
    }

    private static func resetDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let string = value as? String else { return nil }
        if let numeric = Double(string), !string.trimmingCharacters(in: .whitespaces).isEmpty {
            return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1_000 : numeric)
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

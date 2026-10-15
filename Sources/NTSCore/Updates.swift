import Foundation

/// The newest release on GitHub, since the app has no updater of its own.
public enum Updates {
    public static let releasePage = URL(string: "https://github.com/sanderjn/nts-mac/releases/latest")!

    /// The version of the latest release, as in "1.3.0".
    public static func latestVersion() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/sanderjn/nts-mac/releases/latest")!, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Http.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parseVersion(data)
    }

    public static func parseVersion(_ body: Data) throws -> String {
        let tag = try JSONDecoder().decode(Release.self, from: body).tag_name
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Compares number by number, so 1.10.0 is newer than 1.9.0 and 1.2 is the same as 1.2.0.
    public static func isNewer(_ version: String, than current: String) -> Bool {
        let new = numbers(version), old = numbers(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    private struct Release: Decodable {
        let tag_name: String
    }
}

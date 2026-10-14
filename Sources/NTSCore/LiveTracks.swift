import Foundation

public struct Track: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let start: Date

    public init(id: String, title: String, artists: [String], start: Date) {
        self.id = id
        self.title = title
        self.artists = artists
        self.start = start
    }

    public var artist: String { artists.joined(separator: ", ") }

    /// Title first, then artist, in at most `room` characters: the longer of the two is cut first, neither below half.
    public func shortLine(room: Int) -> String {
        guard !artist.isEmpty else { return Self.cut(title, to: room) }
        let titleRoom = max(room - artist.count, room / 2)
        let shownTitle = Self.cut(title, to: titleRoom)
        return "\(shownTitle) – \(Self.cut(artist, to: room - shownTitle.count))"
    }

    private static func cut(_ text: String, to length: Int) -> String {
        text.count > length ? text.prefix(length - 1).trimmingCharacters(in: .whitespaces) + "…" : text
    }
}

/// The tracks NTS recognises on its streams as they play. NTS only shows them to its Supporters.
public enum LiveTracks {
    public enum Failure: Error, Equatable {
        /// Signed in, but this account may not read the tracks.
        case notAllowed
        /// The token was not accepted.
        case notSignedIn
        case unavailable
    }

    /// The name nts.live files a station's tracks under.
    public static func streamID(for station: Station) -> String {
        if station.isLive { return "nts" + station.id.dropFirst("live-".count) }
        return String(station.id.dropFirst("mixtape-".count))
    }

    /// Newest first.
    public static func fetch(streamID: String, idToken: String, limit: Int) async throws -> [Track] {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = query(streamID: streamID, limit: limit)
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { throw Failure.unavailable }
        return try parse(data)
    }

    public static func query(streamID: String, limit: Int) -> Data {
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": "live_tracks"]],
                "where": ["fieldFilter": ["field": ["fieldPath": "stream_id"], "op": "EQUAL", "value": ["stringValue": streamID]]],
                "orderBy": [["field": ["fieldPath": "start_time"], "direction": "DESCENDING"]],
                "limit": limit
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: query, options: [.sortedKeys])
    }

    public static func parse(_ body: Data) throws -> [Track] {
        let decoder = JSONDecoder()
        // A refused query answers with a list holding one error, other failures with a bare error.
        guard let rows = (try? decoder.decode([Row].self, from: body)) ?? (try? decoder.decode(Row.self, from: body)).map({ [$0] }) else {
            throw Failure.unavailable
        }
        if let status = rows.lazy.compactMap(\.error).first?.status {
            throw switch status {
            case "PERMISSION_DENIED": Failure.notAllowed
            case "UNAUTHENTICATED": Failure.notSignedIn
            default: Failure.unavailable
            }
        }
        return rows.compactMap { row in
            // A track that is still being recognised has no title yet.
            guard let document = row.document, let fields = document.fields,
                  let title = fields.song_title?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                  let start = fields.start_time?.timestampValue.flatMap(date) else { return nil }
            let artists = fields.artist_names?.arrayValue?.values?.compactMap(\.stringValue) ?? []
            return Track(id: document.name, title: title, artists: artists, start: start)
        }
    }

    private static let endpoint = URL(string: "https://firestore.googleapis.com/v1/projects/nts-ios-app/databases/(default)/documents:runQuery")!

    private static func date(_ timestamp: String) -> Date? {
        // Firestore writes up to nine decimals, which the parser does not take. Whole seconds are plenty here.
        try? Date.ISO8601FormatStyle().parse(timestamp.replacing(/\.\d+/, with: ""))
    }

    private struct Row: Decodable {
        let document: Document?
        let error: RowError?
    }

    private struct RowError: Decodable {
        let status: String?
    }

    private struct Document: Decodable {
        let name: String
        let fields: Fields?
    }

    private struct Fields: Decodable {
        let song_title: Value?
        let artist_names: Value?
        let start_time: Value?
    }

    private struct Value: Decodable {
        let stringValue: String?
        let timestampValue: String?
        let arrayValue: Values?
    }

    private struct Values: Decodable {
        let values: [Value]?
    }
}

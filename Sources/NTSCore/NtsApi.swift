import Foundation

public enum NtsApi {
    private static let base = "https://www.nts.live/api/v2"

    /// Channel number ("1", "2") to the show that is on now.
    public static func fetchLiveShows() async throws -> [String: LiveShow] {
        try parseLive(await get("\(base)/live"))
    }

    public static func fetchMixtapes() async throws -> [Station] {
        try parseMixtapes(await get("\(base)/mixtapes"))
    }

    public static func parseLive(_ body: Data) throws -> [String: LiveShow] {
        let channels = try JSONDecoder().decode(LiveResponse.self, from: body).results
        var shows: [String: LiveShow] = [:]
        for channel in channels {
            guard let now = channel.now, let title = now.broadcast_title?.unescaped.trimmed else { continue }
            shows[channel.channel_name] = LiveShow(title: title, imageURL: now.embeds?.details?.media?.url)
        }
        return shows
    }

    public static func parseMixtapes(_ body: Data) throws -> [Station] {
        try JSONDecoder().decode(MixtapesResponse.self, from: body).results.compactMap { mixtape in
            guard let endpoint = mixtape.audio_stream_endpoint?.trimmed, !endpoint.isEmpty,
                  let streamURL = URL(string: endpoint) else { return nil }
            let subtitle = mixtape.subtitle?.unescaped.trimmed
            return Station(
                id: "mixtape-\(mixtape.mixtape_alias)",
                title: mixtape.title.unescaped.trimmed,
                subtitle: subtitle?.isEmpty == false ? subtitle : nil,
                streamURL: streamURL,
                isLive: false,
                imageURL: mixtape.media?.url
            )
        }
    }

    private static func get(_ url: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Http.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct LiveResponse: Decodable {
        var results: [LiveChannel] = []
    }

    private struct LiveChannel: Decodable {
        let channel_name: String
        let now: Broadcast?
    }

    private struct Broadcast: Decodable {
        let broadcast_title: String?
        let embeds: Embeds?
    }

    private struct Embeds: Decodable {
        let details: Details?
    }

    private struct Details: Decodable {
        let media: Media?
    }

    private struct Media: Decodable {
        let picture_medium: String?

        var url: URL? { picture_medium.flatMap(URL.init(string:)) }
    }

    private struct MixtapesResponse: Decodable {
        var results: [Mixtape] = []
    }

    private struct Mixtape: Decodable {
        let mixtape_alias: String
        let title: String
        let subtitle: String?
        let audio_stream_endpoint: String?
        let media: Media?
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    // The API returns its texts HTML-escaped: "Fool&#039;s Game", "Tim &amp; Barry".
    var unescaped: String {
        var result = ""
        var rest = self[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let tail = rest[rest.index(after: amp)...]
            if let semi = tail.firstIndex(of: ";"), let character = Self.entity(tail[..<semi]) {
                result += character
                rest = tail[tail.index(after: semi)...]
            } else {
                result += "&"
                rest = tail
            }
        }
        return result + rest
    }

    private static let namedEntities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]

    private static func entity(_ name: Substring) -> String? {
        guard name.hasPrefix("#") else { return namedEntities[String(name)] }
        let digits = name.dropFirst()
        let hex = digits.hasPrefix("x") || digits.hasPrefix("X")
        guard let code = UInt32(hex ? digits.dropFirst() : digits, radix: hex ? 16 : 10),
              let scalar = Unicode.Scalar(code) else { return nil }
        return String(scalar)
    }
}

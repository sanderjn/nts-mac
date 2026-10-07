import Foundation

public struct Station: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let title: String
    public var subtitle: String?
    public let streamURL: URL
    public let isLive: Bool
    public var imageURL: URL?

    public init(id: String, title: String, subtitle: String? = nil, streamURL: URL, isLive: Bool, imageURL: URL? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.streamURL = streamURL
        self.isLive = isLive
        self.imageURL = imageURL
    }
}

public struct LiveShow: Equatable, Sendable {
    public let title: String
    public let imageURL: URL?

    public init(title: String, imageURL: URL?) {
        self.title = title
        self.imageURL = imageURL
    }
}

public enum LiveStations {
    public static let all = [
        Station(id: "live-1", title: "Channel 1", streamURL: URL(string: "https://stream-relay-geo.ntslive.net/stream")!, isLive: true),
        Station(id: "live-2", title: "Channel 2", streamURL: URL(string: "https://stream-relay-geo.ntslive.net/stream2")!, isLive: true)
    ]

    /// `shows` is keyed by channel number ("1", "2").
    public static func withShows(_ shows: [String: LiveShow]) -> [Station] {
        all.map { station in
            var station = station
            let show = shows[String(station.id.dropFirst("live-".count))]
            station.subtitle = show?.title
            station.imageURL = show?.imageURL
            return station
        }
    }
}

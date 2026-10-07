import Foundation

/// What the receiver is asked to play and show.
public struct CastMedia: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let artist: String
    public let imageURL: URL?

    public init(url: URL, title: String, artist: String, imageURL: URL?) {
        self.url = url
        self.title = title
        self.artist = artist
        self.imageURL = imageURL
    }
}

public extension Station {
    /// Live channels lead with the show, mixtapes with their own name.
    var castMedia: CastMedia {
        if isLive, let show = subtitle {
            return CastMedia(url: streamURL, title: show, artist: "NTS \(title)", imageURL: imageURL)
        }
        return CastMedia(url: streamURL, title: title, artist: subtitle ?? "NTS", imageURL: imageURL)
    }
}

/// The receiver app session that plays our media.
public struct CastApp: Equatable, Sendable {
    public let sessionID: String
    public let transportID: String

    public init(sessionID: String, transportID: String) {
        self.sessionID = sessionID
        self.transportID = transportID
    }
}

public struct CastMediaStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case playing, buffering, paused
        case idle(IdleReason)
    }

    public enum IdleReason: Sendable {
        /// The stream finished or failed by itself.
        case ended
        /// Someone stopped it.
        case stopped
        /// Replaced by another load, or not started yet.
        case other
    }

    public let mediaSessionID: Int
    public let state: State

    public init(mediaSessionID: Int, state: State) {
        self.mediaSessionID = mediaSessionID
        self.state = state
    }
}

public enum CastNamespace {
    public static let connection = "urn:x-cast:com.google.cast.tp.connection"
    public static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    public static let receiver = "urn:x-cast:com.google.cast.receiver"
    public static let media = "urn:x-cast:com.google.cast.media"
}

public enum CastPayload {
    /// Google's Default Media Receiver.
    public static let receiverAppID = "CC1AD845"

    public static let connect = json(["type": "CONNECT", "origin": [String: Any]()])
    public static let ping = json(["type": "PING"])
    public static let pong = json(["type": "PONG"])

    public static func launch(requestID: Int) -> String {
        json(["type": "LAUNCH", "appId": receiverAppID, "requestId": requestID])
    }

    public static func getStatus(requestID: Int) -> String {
        json(["type": "GET_STATUS", "requestId": requestID])
    }

    public static func setVolume(_ level: Double, requestID: Int) -> String {
        json(["type": "SET_VOLUME", "volume": ["level": level], "requestId": requestID])
    }

    public static func stopReceiver(sessionID: String, requestID: Int) -> String {
        json(["type": "STOP", "sessionId": sessionID, "requestId": requestID])
    }

    public static func load(_ media: CastMedia, sessionID: String, requestID: Int) -> String {
        var metadata: [String: Any] = ["metadataType": 3, "title": media.title, "artist": media.artist]
        if let imageURL = media.imageURL {
            metadata["images"] = [["url": imageURL.absoluteString]]
        }
        return json([
            "type": "LOAD",
            "sessionId": sessionID,
            "requestId": requestID,
            "autoplay": true,
            "media": [
                "contentId": media.url.absoluteString,
                "contentType": "audio/mpeg",
                "streamType": "LIVE",
                "metadata": metadata
            ] as [String: Any]
        ])
    }

    public static func stopMedia(mediaSessionID: Int, sessionID: String, requestID: Int) -> String {
        json(["type": "STOP", "mediaSessionId": mediaSessionID, "sessionId": sessionID, "requestId": requestID])
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}

/// What an incoming message means to the sender.
public enum CastEvent: Equatable, Sendable {
    case ping
    /// The default media receiver session, or nil when it is not (or no longer) running.
    /// The volume is nil on devices that do not let a sender change it.
    case receiverStatus(CastApp?, volume: Double?)
    case launchError
    /// Nil when the receiver has no media session.
    case mediaStatus(CastMediaStatus?)
    case loadFailed
    case other

    public init(_ message: CastMessage) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(message.payload.utf8)) as? [String: Any],
              let type = object["type"] as? String else {
            self = .other
            return
        }
        switch (message.namespace, type) {
        case (CastNamespace.heartbeat, "PING"):
            self = .ping
        case (CastNamespace.receiver, "RECEIVER_STATUS"):
            let status = object["status"] as? [String: Any]
            let apps = status?["applications"] as? [[String: Any]] ?? []
            let app = apps.first { $0["appId"] as? String == CastPayload.receiverAppID }
            let volume = status?["volume"] as? [String: Any]
            let level = volume?["controlType"] as? String == "fixed" ? nil : volume?["level"] as? Double
            if let sessionID = app?["sessionId"] as? String, let transportID = app?["transportId"] as? String {
                self = .receiverStatus(CastApp(sessionID: sessionID, transportID: transportID), volume: level)
            } else {
                self = .receiverStatus(nil, volume: level)
            }
        case (CastNamespace.receiver, "LAUNCH_ERROR"):
            self = .launchError
        case (CastNamespace.media, "MEDIA_STATUS"):
            let entry = (object["status"] as? [[String: Any]])?.first
            guard let entry, let id = entry["mediaSessionId"] as? Int, let playerState = entry["playerState"] as? String else {
                self = .mediaStatus(nil)
                return
            }
            let state: CastMediaStatus.State
            switch playerState {
            case "PLAYING": state = .playing
            case "BUFFERING": state = .buffering
            case "PAUSED": state = .paused
            default:
                // A fresh load reports idle until it has something to play.
                let extended = entry["extendedStatus"] as? [String: Any]
                switch (entry["idleReason"] as? String, extended?["playerState"] as? String) {
                case (_, "LOADING"): state = .buffering
                case ("FINISHED", _), ("ERROR", _): state = .idle(.ended)
                case ("CANCELLED", _): state = .idle(.stopped)
                default: state = .idle(.other)
                }
            }
            self = .mediaStatus(CastMediaStatus(mediaSessionID: id, state: state))
        case (CastNamespace.media, "LOAD_FAILED"), (CastNamespace.media, "LOAD_CANCELLED"):
            self = .loadFailed
        default:
            self = .other
        }
    }
}

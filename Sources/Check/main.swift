import Foundation
import NTSCore

var failures = 0

@MainActor func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    guard !condition else { return }
    failures += 1
    print("FAIL line \(line): \(message)")
}

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

let shows = try NtsApi.parseLive(fixture("live"))
expect(shows["1"]?.title == "Go Wrong w/ Lina", "channel 1 title")
expect(shows["2"]?.title == "The Heatstroke Boogie w/ Mr. Manns", "channel 2 title")
expect(
    shows["1"]?.imageURL?.absoluteString == "https://media.ntslive.co.uk/resize/400x400/9125b330-a3a7-4377-bc15-f2773922c4bd_1789948800.jpeg",
    "channel 1 artwork"
)

let partial = try NtsApi.parseLive(Data(#"{"results":[{"channel_name":"1"},{"channel_name":"2","now":{"broadcast_title":" X "}}]}"#.utf8))
expect(partial == ["2": LiveShow(title: "X", imageURL: nil)], "channel without broadcast is skipped, title trimmed")

let escaped = try NtsApi.parseLive(Data(#"{"results":[{"channel_name":"1","now":{"broadcast_title":"Fool&#039;s Game w/ Tim &amp; Barry"}},{"channel_name":"2","now":{"broadcast_title":"A &#x27;B&#x27; &amp;lt; R&B; &bogus; &#xD800;"}}]}"#.utf8))
expect(escaped["1"]?.title == "Fool's Game w/ Tim & Barry", "html entities in a title are decoded")
expect(escaped["2"]?.title == "A 'B' &lt; R&B; &bogus; &#xD800;", "entities decode once, unknown ones stay")

let mixtapes = try NtsApi.parseMixtapes(fixture("mixtapes"))
expect(mixtapes.count == 16, "16 mixtapes")
expect(mixtapes.first?.title == "Poolside", "first mixtape title")
expect(mixtapes.first?.streamURL.absoluteString == "https://stream-mixtape-geo.ntslive.net/mixtape4", "first mixtape stream")
expect(mixtapes.first?.id.hasPrefix("mixtape-") == true, "mixtape id prefix")
expect(mixtapes.first?.isLive == false, "mixtape is not live")
expect(
    mixtapes.first?.imageURL?.absoluteString == "https://media.ntslive.co.uk/resize/400x400/cf5afb01-5a68-4fa0-a1c6-415b35d09ed6_1542931200.jpeg",
    "first mixtape artwork"
)
expect(Set(mixtapes.map(\.id)).count == mixtapes.count, "mixtape ids are unique")

let streamless = try NtsApi.parseMixtapes(Data(#"{"results":[{"mixtape_alias":"a","title":"A","subtitle":""},{"mixtape_alias":"b","title":"B","audio_stream_endpoint":"https://x"}]}"#.utf8))
expect(streamless.map(\.title) == ["B"], "mixtape without stream is dropped")
expect(streamless.first?.subtitle == nil, "missing subtitle stays nil")

let stations = LiveStations.withShows(["2": LiveShow(title: "Show", imageURL: URL(string: "https://img"))])
expect(stations[0].subtitle == nil && stations[0].imageURL == nil, "channel without show stays bare")
expect(stations[1].subtitle == "Show" && stations[1].imageURL?.absoluteString == "https://img", "channel 2 gets its show")

let frame = CastMessage(destination: "receiver-0", namespace: CastNamespace.receiver, payload: CastPayload.launch(requestID: 7)).framed()
expect(frame.prefix(4).reduce(0) { $0 << 8 | Int($1) } == frame.count - 4, "frame is prefixed with its body length")
let decoded = CastMessage(decoding: frame.dropFirst(4))
expect(decoded?.source == "sender-0" && decoded?.destination == "receiver-0", "frame round trip keeps the route")
expect(decoded?.payload == #"{"appId":"CC1AD845","requestId":7,"type":"LAUNCH"}"#, "frame round trip keeps the payload")
expect(CastMessage(decoding: Data([0x12, 0x05, 0x61])) == nil, "truncated frame is rejected")
let long = CastMessage(destination: "x", namespace: "y", payload: String(repeating: "é", count: 200))
expect(CastMessage(decoding: long.encoded()) == long, "multi-byte lengths and UTF-8 survive")

func event(_ namespace: String, _ payload: String) -> CastEvent {
    CastEvent(CastMessage(source: "receiver-0", destination: "*", namespace: namespace, payload: payload))
}

expect(event(CastNamespace.heartbeat, #"{"type":"PING"}"#) == .ping, "ping")
expect(
    event(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","sessionId":"s1","transportId":"t1"}]}}"#)
        == .receiverStatus(CastApp(sessionID: "s1", transportID: "t1"), volume: nil),
    "receiver status with our app"
)
expect(
    event(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"YouTube","sessionId":"s","transportId":"t"}]}}"#) == .receiverStatus(nil, volume: nil),
    "another app is not ours"
)
expect(event(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","status":{"volume":{"level":1}}}"#) == .receiverStatus(nil, volume: 1), "no app running")
expect(
    event(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","status":{"volume":{"controlType":"attenuation","level":0.35,"muted":false}}}"#) == .receiverStatus(nil, volume: 0.35),
    "adjustable volume"
)
expect(
    event(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","status":{"volume":{"controlType":"fixed","level":1}}}"#) == .receiverStatus(nil, volume: nil),
    "a fixed volume is not offered"
)
expect(CastPayload.setVolume(0.5, requestID: 4) == #"{"requestId":4,"type":"SET_VOLUME","volume":{"level":0.5}}"#, "set volume payload")
expect(
    event(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"PLAYING"}]}"#)
        == .mediaStatus(CastMediaStatus(mediaSessionID: 3, state: .playing)),
    "playing"
)
expect(
    event(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"IDLE","idleReason":"ERROR"}]}"#)
        == .mediaStatus(CastMediaStatus(mediaSessionID: 3, state: .idle(.ended))),
    "a failed stream counts as ended"
)
expect(
    event(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"IDLE","idleReason":"INTERRUPTED"}]}"#)
        == .mediaStatus(CastMediaStatus(mediaSessionID: 3, state: .idle(.other))),
    "a replaced stream does not count as ended"
)
expect(
    event(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"IDLE","idleReason":"CANCELLED"}]}"#)
        == .mediaStatus(CastMediaStatus(mediaSessionID: 3, state: .idle(.stopped))),
    "a stopped stream"
)
expect(
    event(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"IDLE","extendedStatus":{"playerState":"LOADING"}}]}"#)
        == .mediaStatus(CastMediaStatus(mediaSessionID: 3, state: .buffering)),
    "a load in progress counts as buffering"
)
expect(event(CastNamespace.media, #"{"type":"MEDIA_STATUS","status":[]}"#) == .mediaStatus(nil), "no media session")
expect(event(CastNamespace.media, #"{"type":"LOAD_FAILED"}"#) == .loadFailed, "load failed")
expect(event(CastNamespace.media, "nonsense") == .other, "unreadable payload is ignored")

let liveMedia = stations[1].castMedia
expect(liveMedia.title == "Show" && liveMedia.artist == "NTS Channel 2", "live channel leads with the show")
expect(stations[0].castMedia.title == "Channel 1" && stations[0].castMedia.artist == "NTS", "channel without show falls back to its name")
expect(mixtapes[0].castMedia.title == "Poolside", "mixtape leads with its name")
let load = CastPayload.load(liveMedia, sessionID: "s1", requestID: 2)
expect(load.contains(#""contentId":"\#(stations[1].streamURL.absoluteString)""#), "load carries the stream url unescaped")
expect(load.contains(#""images":[{"url":"https://img"}]"#), "load carries the artwork")

print(failures == 0 ? "OK" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

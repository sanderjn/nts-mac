import Foundation
import Network

/// Serves one stream to Cast devices from this Mac, starting with the last seconds it has already heard.
///
/// The Default Media Receiver stays silent until it has buffered about 16 s of a progressive stream.
/// NTS sends only 3 s at once and the rest in real time, so a cast took 16 s to make a sound.
/// Handed 8 s at once, the receiver starts in a third of a second, and ends up 8 s behind live instead of 18.
@MainActor
public final class CastRelay {
    /// How much a receiver gets at once.
    static let head = 8.0
    /// How much is kept, a little more than the head so it is always full.
    static let keep = 12.0
    /// How long a receiver waits for the head to fill before it gets what there is.
    static let patience = 8.0

    private var listener: NWListener?
    private var upstream: Upstream?
    private var source: URL?
    // Changes with the source, so a new stream is a new URL and the receiver loads it afresh.
    private var generation = 0
    private var buffer: [UInt8] = []
    private var bytesPerSecond = 32_000.0
    private var clients: [ObjectIdentifier: Client] = [:]
    private var retry: Task<Void, Never>?

    public init() {}

    /// Starts filling the buffer from `url`, so a cast of it can start at once. Does nothing if it already is.
    public func follow(_ url: URL) {
        guard url != source else { return }
        stop()
        source = url
        generation += 1
        listen()
        connect()
    }

    /// The URL a receiver on the local network plays `url` from, or nil when the relay cannot serve it.
    public func url(for url: URL) -> URL? {
        guard url == source, let port = listener?.port, let host = Self.lanAddress() else { return nil }
        return URL(string: "http://\(host):\(port.rawValue)/\(generation)")
    }

    /// Closes the port too, for when Cast is turned off.
    public func close() {
        stop()
        listener?.cancel()
        listener = nil
    }

    public func stop() {
        retry?.cancel()
        retry = nil
        upstream?.cancel()
        upstream = nil
        source = nil
        buffer = []
        for client in clients.values { client.connection.cancel() }
        clients = [:]
    }

    // MARK: Upstream

    private func connect() {
        guard let source else { return }
        let generation = generation
        upstream = Upstream(url: source, onResponse: { [weak self] bitrate in
            guard let self, generation == self.generation, let bitrate else { return }
            self.bytesPerSecond = Double(bitrate) * 1000 / 8
        }, onData: { [weak self] data in
            guard let self, generation == self.generation else { return }
            self.receive(data)
        }, onEnd: { [weak self] in
            guard let self, generation == self.generation else { return }
            // Receivers keep their connection and hear the new connection's audio after a short gap.
            // The buffer starts over, so a new receiver never gets the seam between the two.
            self.upstream = nil
            self.buffer = []
            self.retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, generation == self.generation else { return }
                self.connect()
            }
        })
    }

    private func receive(_ data: Data) {
        let bytes = [UInt8](data)
        buffer.append(contentsOf: bytes)
        let limit = Int(Self.keep * bytesPerSecond)
        if buffer.count > limit + 64 * 1024 { buffer.removeFirst(buffer.count - limit) }
        for client in clients.values {
            if client.started {
                send(bytes, to: client)
            } else if Double(buffer.count) >= Self.head * bytesPerSecond {
                start(client)
            }
        }
    }

    // MARK: Receivers

    /// Opens the port receivers connect to. It takes a moment, so this comes well before the first cast.
    public func listen() {
        guard listener == nil, let listener = try? NWListener(using: .tcp) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, case .failed = state else { return }
                self.listener?.cancel()
                self.listener = nil
            }
        }
        listener.start(queue: .main)
    }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection)
        let id = ObjectIdentifier(client)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled:
                    self?.clients[id] = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        let generation = generation
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] request, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, self.clients[id] != nil else { return }
                guard generation == self.generation, let request, Self.path(of: Data(request)) == "/\(generation)" else {
                    connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                client.requested = true
                if Double(self.buffer.count) >= Self.head * self.bytesPerSecond {
                    self.start(client)
                } else {
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(Self.patience))
                        guard let self, generation == self.generation, self.clients[id] != nil, !client.started else { return }
                        self.start(client)
                    }
                }
            }
        }
    }

    private func start(_ client: Client) {
        guard client.requested, !client.started else { return }
        client.started = true
        let header = "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        send(Array(header.utf8), to: client)
        let from = max(0, buffer.count - Int(Self.head * bytesPerSecond))
        if let frame = Self.frameStart(in: buffer, from: from) {
            send(Array(buffer[frame...]), to: client)
        }
    }

    private func send(_ bytes: [UInt8], to client: Client) {
        // A receiver that stops reading is dropped rather than buffered for without end.
        guard client.pending < 1 << 21 else {
            client.connection.cancel()
            return
        }
        client.pending += bytes.count
        client.connection.send(content: Data(bytes), completion: .contentProcessed { [weak client] _ in
            MainActor.assumeIsolated { client?.pending -= bytes.count }
        })
    }

    // MARK: Helpers

    /// The path of an HTTP request line, such as "/3" for "GET /3 HTTP/1.1".
    nonisolated public static func path(of request: Data) -> String? {
        guard let line = String(decoding: request, as: UTF8.self).split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" || parts[0] == "HEAD" else { return nil }
        return String(parts[1].split(separator: "?").first ?? "")
    }

    /// The first MPEG audio frame at or after `from`, checked against the frame after it where that can be worked out.
    nonisolated public static func frameStart(in bytes: [UInt8], from: Int) -> Int? {
        var index = max(0, from)
        while index + 4 <= bytes.count {
            if let length = frameLength(bytes, at: index) {
                let next = index + length
                if next + 4 > bytes.count || frameLength(bytes, at: next) != nil { return index }
            }
            index += 1
        }
        return nil
    }

    /// The length of the MPEG-1/2 Layer III frame whose header starts at `index`, or nil if none does.
    nonisolated private static func frameLength(_ bytes: [UInt8], at index: Int) -> Int? {
        guard index + 4 <= bytes.count else { return nil }
        let b1 = bytes[index + 1], b2 = bytes[index + 2]
        guard bytes[index] == 0xFF, b1 & 0xE0 == 0xE0 else { return nil }
        let version = (b1 >> 3) & 0b11  // 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5
        let layer = (b1 >> 1) & 0b11    // 1 = Layer III
        let bitrateIndex = Int(b2 >> 4)
        let rateIndex = Int((b2 >> 2) & 0b11)
        guard version != 1, layer == 1, bitrateIndex != 0, bitrateIndex != 15, rateIndex != 3 else { return nil }
        let mpeg1 = version == 3
        let bitrates = mpeg1
            ? [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
            : [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
        let rates = [44100, 48000, 32000][rateIndex] / (mpeg1 ? 1 : version == 2 ? 2 : 4)
        let padding = Int((b2 >> 1) & 1)
        return (mpeg1 ? 144 : 72) * bitrates[bitrateIndex] * 1000 / rates + padding
    }

    /// This Mac's IPv4 address on the local network, preferring the built-in Wi-Fi or Ethernet.
    nonisolated static func lanAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var found: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(bitPattern: entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // Self-assigned addresses are not on the network the receiver is on.
            guard !text.hasPrefix("169.254.") else { continue }
            found.append((name, text))
        }
        return found.sorted { $0.name < $1.name }.first?.address
    }
}

@MainActor
private final class Client {
    let connection: NWConnection
    var requested = false
    var started = false
    var pending = 0

    init(_ connection: NWConnection) {
        self.connection = connection
    }
}

/// Reads an endless HTTP stream on the main queue.
private final class Upstream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onResponse: @MainActor (Int?) -> Void
    private let onData: @MainActor (Data) -> Void
    private let onEnd: @MainActor () -> Void
    private var session: URLSession?

    @MainActor
    init(url: URL, onResponse: @escaping @MainActor (Int?) -> Void, onData: @escaping @MainActor (Data) -> Void, onEnd: @escaping @MainActor () -> Void) {
        self.onResponse = onResponse
        self.onData = onData
        self.onEnd = onEnd
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": Http.userAgent]
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session
        session.dataTask(with: url).resume()
    }

    @MainActor
    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let ok = http.map { (200..<300).contains($0.statusCode) } ?? false
        let bitrate = (http?.value(forHTTPHeaderField: "icy-br")).flatMap { Int($0.split(separator: ",").first ?? "") }
        MainActor.assumeIsolated { if ok { onResponse(bitrate) } }
        completionHandler(ok ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated { onData(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // An invalidated session also ends here, after `cancel`.
        guard self.session != nil else { return }
        MainActor.assumeIsolated { onEnd() }
    }
}

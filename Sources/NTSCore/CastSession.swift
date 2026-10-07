import Foundation
import Network

/// Plays one stream on a Cast device through Google's default media receiver.
/// Stopping ends the media session, so resuming is always live.
@MainActor
public final class CastSession {
    public enum Status: Sendable {
        case idle, loading, playing
    }

    public var onStatusChange: ((Status) -> Void)?
    public var onVolumeChange: ((Double?) -> Void)?
    /// From 0 to 1. Nil while not connected, and on devices with a fixed volume.
    public private(set) var volume: Double?

    private let device: CastDevice
    private var status = Status.idle
    private var connection: NWConnection?
    private var generation = 0
    private var app: CastApp?
    private var launching = false
    // Whether this session put something on the receiver, as opposed to finding it running.
    private var started = false
    private var mediaSessionID: Int?
    // A stop that came before the receiver named the media session it has to stop.
    private var stopPending = false
    private var wanted: CastMedia?
    private var requestID = 0
    private var lastHeard = Date.now
    private var heartbeat: Task<Void, Never>?
    private var reload: Task<Void, Never>?
    private var volumeSetAt = Date.distantPast
    private var volumeSend: Task<Void, Never>?

    public init(device: CastDevice) {
        self.device = device
    }

    public func play(_ media: CastMedia) {
        guard media != wanted || status == .idle else { return }
        wanted = media
        stopPending = false
        report(.loading)
        if connection == nil {
            open()
        } else if app != nil {
            load()
        } else if connection?.state == .ready {
            launch()
        }
    }

    /// Connects without starting anything, so the volume is known before the first play.
    public func connect() {
        if connection == nil { open() }
    }

    public func setVolume(_ level: Double) {
        guard volume != nil else { return }
        volume = level
        volumeSetAt = .now
        guard volumeSend == nil else { return }
        // A drag changes the level far more often than the device needs to hear about it.
        volumeSend = Task { [weak self] in
            var sent: Double?
            while let self, let level = self.volume, !Task.isCancelled {
                if level != sent {
                    self.send(CastPayload.setVolume(level, requestID: self.nextRequestID()), CastNamespace.receiver)
                    sent = level
                } else if self.volumeSetAt.timeIntervalSinceNow < -1 {
                    // Statuses were ignored while the level was being set, so ask for the one that stuck.
                    self.send(CastPayload.getStatus(requestID: self.nextRequestID()), CastNamespace.receiver)
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !Task.isCancelled { self?.volumeSend = nil }
        }
    }

    public func stop() {
        wanted = nil
        reload?.cancel()
        if let mediaSessionID {
            stopMedia(mediaSessionID)
        } else {
            stopPending = app != nil
        }
        report(.idle)
    }

    /// Ends the session for good, without reporting it.
    public func close(stoppingReceiver: Bool) {
        onStatusChange = nil
        onVolumeChange = nil
        if stoppingReceiver, started, let app, let connection {
            let stop = CastMessage(destination: "receiver-0", namespace: CastNamespace.receiver, payload: CastPayload.stopReceiver(sessionID: app.sessionID, requestID: nextRequestID()))
            connection.stateUpdateHandler = nil
            connection.send(content: stop.framed(), completion: .contentProcessed { _ in connection.cancel() })
            self.connection = nil
        }
        tearDown()
    }

    private func open() {
        let tls = NWProtocolTLS.Options()
        // Cast devices present a self-signed certificate.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .main)
        let connection = NWConnection(to: device.endpoint, using: NWParameters(tls: tls))
        self.connection = connection
        generation += 1
        lastHeard = .now

        let generation = generation
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, generation == self.generation else { return }
                switch state {
                case .ready:
                    self.send(CastPayload.connect, CastNamespace.connection)
                    if self.wanted != nil {
                        self.launch()
                    } else {
                        self.send(CastPayload.getStatus(requestID: self.nextRequestID()), CastNamespace.receiver)
                    }
                    self.receive()
                case .failed, .cancelled, .waiting:
                    self.end()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)

        // Also covers a device that never answers the connection attempt.
        heartbeat = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard let self, generation == self.generation else { return }
                if lastHeard.timeIntervalSinceNow < -15 {
                    end()
                    return
                }
                if connection.state == .ready { send(CastPayload.ping, CastNamespace.heartbeat) }
            }
        }
    }

    private func launch() {
        guard !launching else { return }
        launching = true
        started = true
        send(CastPayload.launch(requestID: nextRequestID()), CastNamespace.receiver)
    }

    private func load() {
        guard let wanted, let app else { return }
        reload?.cancel()
        started = true
        send(CastPayload.load(wanted, sessionID: app.sessionID, requestID: nextRequestID()), CastNamespace.media, to: app.transportID)
    }

    private func stopMedia(_ id: Int) {
        guard let app else { return }
        send(CastPayload.stopMedia(mediaSessionID: id, sessionID: app.sessionID, requestID: nextRequestID()), CastNamespace.media, to: app.transportID)
        mediaSessionID = nil
        stopPending = false
    }

    private func scheduleReload() {
        reload?.cancel()
        reload = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.load()
        }
    }

    private func handle(_ message: CastMessage) {
        lastHeard = .now
        switch CastEvent(message) {
        case .ping:
            send(CastPayload.pong, CastNamespace.heartbeat)
        case .receiverStatus(let running, let level):
            // The device echoes every level it is sent, which would drag the slider back mid-drag.
            if level != volume, volumeSetAt.timeIntervalSinceNow < -1 {
                volume = level
                onVolumeChange?(level)
            }
            if let running {
                guard running != app else { return }
                app = running
                launching = false
                send(CastPayload.connect, CastNamespace.connection, to: running.transportID)
                load()
            } else if app != nil {
                // Something else took over the receiver, or it closed our idle app. The volume is still the device's.
                app = nil
                started = false
                mediaSessionID = nil
                stopPending = false
                wanted = nil
                reload?.cancel()
                report(.idle)
            }
        case .launchError:
            end()
        case .mediaStatus(let status):
            guard let status else { return }
            if case .idle(let reason) = status.state {
                // A replaced session reports idle after its successor has started.
                guard status.mediaSessionID == mediaSessionID else { return }
                mediaSessionID = nil
                guard wanted != nil else { return }
                switch reason {
                case .ended:
                    report(.loading)
                    scheduleReload()
                case .stopped:
                    // Stopped from another controller.
                    report(.idle)
                case .other:
                    break
                }
                return
            }
            mediaSessionID = status.mediaSessionID
            guard wanted != nil else {
                if stopPending { stopMedia(status.mediaSessionID) }
                return
            }
            switch status.state {
            case .playing:
                report(.playing)
            case .buffering:
                report(.loading)
            case .paused:
                // Paused from the receiver's own remote, which can also resume it.
                report(.idle)
            case .idle:
                break
            }
        case .loadFailed:
            if wanted != nil { scheduleReload() }
        case .other:
            break
        }
    }

    private func receive() {
        let generation = generation
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, generation == self.generation else { return }
                let length = header?.count == 4 ? header!.reduce(0) { $0 << 8 | Int($1) } : 0
                guard length > 0, length <= 1 << 20 else {
                    self.end()
                    return
                }
                self.connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, _ in
                    MainActor.assumeIsolated {
                        guard let self, generation == self.generation else { return }
                        guard let body, body.count == length else {
                            self.end()
                            return
                        }
                        if let message = CastMessage(decoding: body) { self.handle(message) }
                        if generation == self.generation { self.receive() }
                    }
                }
            }
        }
    }

    private func send(_ payload: String, _ namespace: String, to destination: String = "receiver-0") {
        let message = CastMessage(destination: destination, namespace: namespace, payload: payload)
        connection?.send(content: message.framed(), completion: .contentProcessed { _ in })
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }

    private func report(_ status: Status) {
        self.status = status
        onStatusChange?(status)
    }

    /// The connection dropped. The next `play` reconnects.
    private func end() {
        tearDown()
        report(.idle)
    }

    private func tearDown() {
        generation += 1
        heartbeat?.cancel()
        reload?.cancel()
        volumeSend?.cancel()
        volumeSend = nil
        volumeSetAt = .distantPast
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        app = nil
        launching = false
        started = false
        mediaSessionID = nil
        stopPending = false
        wanted = nil
        if volume != nil {
            volume = nil
            onVolumeChange?(nil)
        }
    }
}

import AVFoundation

/// Plays one endless stream. Stopping drops the connection, so resuming is always live.
@MainActor
final class StreamPlayer {
    enum Status {
        case idle, loading, playing
    }

    var onStatusChange: ((Status) -> Void)?

    let player = AVPlayer()
    private var url: URL?
    private var observation: NSKeyValueObservation?
    private var reconnect: Task<Void, Never>?

    init() {
        observation = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.sync() }
        }
    }

    func play(_ url: URL) {
        self.url = url
        connect()
    }

    func stop() {
        url = nil
        reconnect?.cancel()
        reconnect = nil
        player.replaceCurrentItem(with: nil)
        onStatusChange?(.idle)
    }

    private func connect() {
        guard let url else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        onStatusChange?(.loading)
        scheduleReconnect(after: 10)
    }

    private func sync() {
        guard url != nil else { return }
        switch player.timeControlStatus {
        case .playing:
            reconnect?.cancel()
            reconnect = nil
            onStatusChange?(.playing)
        case .waitingToPlayAtSpecifiedRate:
            onStatusChange?(.loading)
            if reconnect == nil { scheduleReconnect(after: 10) }
        case .paused:
            // Nothing pauses the player but a failed or ended stream.
            onStatusChange?(.loading)
            if reconnect == nil { scheduleReconnect(after: 3) }
        @unknown default:
            break
        }
    }

    private func scheduleReconnect(after seconds: Double) {
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.reconnect = nil
            self.connect()
        }
    }
}

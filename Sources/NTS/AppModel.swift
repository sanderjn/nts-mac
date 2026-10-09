import AppKit
import AVFoundation
import MediaPlayer
import NTSCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    enum Playback {
        case stopped, loading, playing
    }

    private(set) var live = LiveStations.all
    private(set) var mixtapes: [Station] = []
    private(set) var currentID: String?
    private(set) var playback = Playback.stopped
    /// Counts up while loading, for the spinner in the menu bar.
    private(set) var loadingStep = 0
    private(set) var castDevices: [CastDevice] = []
    /// Nil plays on this Mac.
    private(set) var castDevice: CastDevice?
    /// From 0 to 1. Nil when not connected to a Cast device, or when the device does not let its volume be set.
    private(set) var castVolume: Double?
    private(set) var showsCast = UserDefaults.standard.object(forKey: showsCastKey) as? Bool ?? true
    private(set) var showsAirPlay = UserDefaults.standard.object(forKey: showsAirPlayKey) as? Bool ?? true
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let player = StreamPlayer()
    @ObservationIgnored private let castBrowser = CastBrowser()
    @ObservationIgnored private var castSession: CastSession?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var hasPlayed = false
    @ObservationIgnored private var loadingTicker: Task<Void, Never>?
    // Keeps the last station playable before the mixtape list has loaded.
    @ObservationIgnored private var saved: Station?
    @ObservationIgnored private var artwork: (url: URL, image: NSImage)?
    @ObservationIgnored private var artworkLoading: URL?

    private static let lastStationKey = "lastStation"
    private static let showsCastKey = "showsCast"
    private static let showsAirPlayKey = "showsAirPlay"

    var current: Station? {
        (live + mixtapes).first { $0.id == currentID } ?? saved
    }

    /// For the AirPlay route picker.
    var localPlayer: AVPlayer { player.player }

    init() {
        saved = UserDefaults.standard.data(forKey: Self.lastStationKey).flatMap { try? JSONDecoder().decode(Station.self, from: $0) }
        currentID = saved?.id
        player.onStatusChange = { [weak self] in self?.update(Playback($0)) }
        castBrowser.onChange = { [weak self] in self?.castDevices = $0 }
        if showsCast { castBrowser.start() }
        registerRemoteCommands()
        // The local stream breaks during sleep anyway; without this it would reconnect and blare on wake.
        // A cast keeps playing on its own device.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.castSession == nil else { return }
                self.pause()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfStale() }
        }
        Task { [weak self] in
            while let self {
                if playback != .stopped || lastRefresh == .distantPast { await refresh() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func select(_ station: Station) {
        if station.id == currentID, playback != .stopped {
            pause()
        } else {
            play(station)
        }
    }

    func toggle() {
        if playback != .stopped {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        if let castSession {
            castSession.stop()
        } else {
            player.stop()
        }
    }

    /// Moves playback to a Cast device, or back to this Mac with nil.
    func cast(to device: CastDevice?) {
        guard device?.id != castDevice?.id else { return }
        let wasPlaying = playback != .stopped
        castSession?.close(stoppingReceiver: true)
        castSession = nil
        player.stop()
        castDevice = device
        castVolume = nil
        if let device {
            let session = CastSession(device: device)
            session.onStatusChange = { [weak self] in self?.update(Playback($0)) }
            session.onVolumeChange = { [weak self] in self?.castVolume = $0 }
            session.connect()
            castSession = session
        }
        update(.stopped)
        if wasPlaying, let current { play(current) }
    }

    /// Without Cast the app never looks at the local network.
    func setShowsCast(_ shows: Bool) {
        showsCast = shows
        UserDefaults.standard.set(shows, forKey: Self.showsCastKey)
        if shows {
            castBrowser.start()
        } else {
            cast(to: nil)
            castBrowser.stop()
            castDevices = []
        }
    }

    func setShowsAirPlay(_ shows: Bool) {
        showsAirPlay = shows
        UserDefaults.standard.set(shows, forKey: Self.showsAirPlayKey)
    }

    func setLaunchesAtLogin(_ launches: Bool) {
        if launches {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        refreshLaunchesAtLogin()
    }

    /// The login item can also be removed in System Settings.
    func refreshLaunchesAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setCastVolume(_ level: Double) {
        guard castVolume != nil else { return }
        castVolume = level
        castSession?.setVolume(level)
    }

    func resume() {
        guard playback == .stopped else { return }
        play(current ?? live[0])
    }

    func statusLabel(for station: Station) -> String? {
        guard station.id == currentID else { return nil }
        return switch playback {
        case .playing: "Playing"
        case .loading: "Loading"
        case .stopped: hasPlayed ? "Paused" : nil
        }
    }

    private func play(_ station: Station) {
        currentID = station.id
        saved = station
        UserDefaults.standard.set(try? JSONEncoder().encode(station), forKey: Self.lastStationKey)
        hasPlayed = true
        if let castSession {
            castSession.play(station.castMedia)
        } else {
            player.play(station.streamURL)
        }
        refreshIfStale()
    }

    private func update(_ playback: Playback) {
        self.playback = playback
        if playback != .loading {
            loadingTicker?.cancel()
            loadingTicker = nil
        } else if loadingTicker == nil {
            loadingTicker = Task { [weak self] in
                while (try? await Task.sleep(for: .milliseconds(100))) != nil {
                    self?.loadingStep += 1
                }
            }
        }
        publishNowPlaying()
    }

    private func refreshIfStale() {
        guard lastRefresh.timeIntervalSinceNow < -30 else { return }
        Task { await refresh() }
    }

    private func refresh() async {
        lastRefresh = .now
        async let shows = try? NtsApi.fetchLiveShows()
        async let tapes = mixtapes.isEmpty ? try? NtsApi.fetchMixtapes() : nil
        if let shows = await shows { live = LiveStations.withShows(shows) }
        if let tapes = await tapes, !tapes.isEmpty { mixtapes = tapes }
        // The receiver shows what it was given at load time, so a new show needs a new load.
        // That costs a few seconds of silence, which a speaker has nothing to show for.
        if let castSession, castDevice?.hasDisplay == true, playback != .stopped, let current {
            castSession.play(current.castMedia)
        }
        publishNowPlaying()
    }

    // MARK: - Now Playing and media keys

    private func publishNowPlaying() {
        // Publishing before the first play would steal the media keys from whatever else is open.
        guard hasPlayed, let station = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: station.title,
            MPMediaItemPropertyArtist: station.subtitle ?? "NTS",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let url = station.imageURL {
            if let artwork, artwork.url == url {
                info[MPMediaItemPropertyArtwork] = Self.mediaArtwork(artwork.image)
            } else {
                loadArtwork(url)
            }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = playback == .stopped ? .paused : .playing
    }

    private func loadArtwork(_ url: URL) {
        guard artworkLoading != url else { return }
        artworkLoading = url
        Task {
            defer { if artworkLoading == url { artworkLoading = nil } }
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = NSImage(data: data) else { return }
            guard current?.imageURL == url else { return }
            artwork = (url, image)
            publishNowPlaying()
        }
    }

    // The system calls these handlers off the main thread, so they must not inherit main actor isolation.
    private nonisolated static func mediaArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private nonisolated func registerRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.toggle() }
            return .success
        }
        for command in [commands.nextTrackCommand, commands.previousTrackCommand, commands.changePlaybackPositionCommand] {
            command.isEnabled = false
        }
    }
}

private extension AppModel.Playback {
    init(_ status: StreamPlayer.Status) {
        self = switch status {
        case .idle: .stopped
        case .loading: .loading
        case .playing: .playing
        }
    }

    init(_ status: CastSession.Status) {
        self = switch status {
        case .idle: .stopped
        case .loading: .loading
        case .playing: .playing
        }
    }
}

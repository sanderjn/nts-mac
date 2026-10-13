import AVKit
import NTSCore
import SwiftUI

struct Artwork: View {
    let url: URL?

    var body: some View {
        Color(white: 0.12)
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .clipped()
    }
}

struct StatusBadge: View {
    let label: String

    var body: some View {
        Text(label.uppercased())
            .font(Theme.bold(12))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.bold(13))
            .foregroundStyle(.white.opacity(0.6))
    }
}

struct NowPlayingHeader: View {
    @Environment(AppModel.self) private var model
    // As tall as the title and subtitle are from cap to baseline, so the image lines up with both.
    private let imageSize: CGFloat = 36

    var body: some View {
        VStack(spacing: 10) {
            controls
            if let volume = model.castVolume {
                CastVolumeSlider(volume: volume)
            }
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Group {
                if let image = model.current?.imageURL {
                    Artwork(url: image)
                } else {
                    Image(nsImage: Theme.logo)
                        .resizable()
                        .renderingMode(.template)
                }
            }
            .frame(width: imageSize, height: imageSize)
            .padding(.trailing, 8)
            VStack(alignment: .leading, spacing: 1) {
                Text((model.current?.title ?? "Nothing playing").uppercased())
                    .font(Theme.bold(18))
                if let subtitle = model.current?.subtitle {
                    Text(subtitle.uppercased())
                        .font(Theme.regular(15))
                        .opacity(0.7)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if model.showsCast {
                CastButton()
            }
            if model.showsAirPlay {
                AirPlayButton(player: model.localPlayer)
                    .frame(width: 28, height: 36)
            }
            Button(action: model.toggle) {
                Image(systemName: model.playback == .stopped ? "play.fill" : "pause.fill")
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(model.playback == .stopped ? "Play" : "Pause")
        }
    }
}

/// The playing track as a row of its own, for where there is no track list to find it in.
struct PlayingTrackRow: View {
    let track: Track
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            track.copy()
            copied = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // Room for the check mark, so the text stays put when it takes the dot's place.
                    Group {
                        if copied {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        } else {
                            PlayingDot()
                        }
                    }
                    .frame(width: markWidth, alignment: .leading)
                    Text(track.title.uppercased())
                        .font(Theme.bold(14))
                }
                if !track.artist.isEmpty {
                    Text(track.artist.uppercased())
                        .font(Theme.regular(13))
                        .opacity(0.7)
                        .padding(.leading, markWidth + 6)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(hovering ? .black : .white)
            .background(hovering ? .white : .black)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy \(track.line)")
        .task(id: copied) { await copied.clearsAfterAMoment { copied = false } }
    }

    private let markWidth: CGFloat = 10
}

struct PlayingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var faded = false

    var body: some View {
        Circle()
            .fill(Theme.red)
            .frame(width: 6, height: 6)
            .opacity(faded ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever()) { faded = true }
            }
            .accessibilityLabel("Playing now")
    }
}

extension Track {
    var line: String { artist.isEmpty ? title : "\(artist) – \(title)" }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(line, forType: .string)
    }
}

extension Bool {
    /// For a "copied" mark that should go away by itself.
    @MainActor
    func clearsAfterAMoment(_ clear: () -> Void) async {
        guard self else { return }
        try? await Task.sleep(for: .seconds(1.5))
        clear()
    }
}

struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.bold(13))
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
                .foregroundStyle(hovering ? .black : .white)
                .background(hovering ? .white : .black)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A cell in a bar of them, as tall as the bar and set apart from its neighbours by lines.
struct BarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .foregroundStyle(hovering ? .black : .white)
                .background(hovering ? .white : .black)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CastVolumeSlider: View {
    @Environment(AppModel.self) private var model
    let volume: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            Slider(value: Binding { volume } set: { model.setCastVolume($0) })
                .controlSize(.small)
                .tint(.white)
                .accessibilityLabel("Volume on \(model.castDevice?.name ?? "the Cast device")")
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 11))
        // The slider would otherwise follow the system appearance onto the black background.
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Shows the Dock icon for as long as a window is open; the app otherwise only lives in the menu bar.
    func showsDockIconWhileOpen() -> some View {
        onAppear {
            OpenWindows.count += 1
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            OpenWindows.count -= 1
            if OpenWindows.count <= 0 { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@MainActor
private enum OpenWindows {
    static var count = 0
}

struct CastButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Picker("Play on", selection: selection) {
                Text("This Mac").tag(String?.none)
                ForEach(devices) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
            }
            .pickerStyle(.inline)
            if devices.isEmpty {
                Text("No Cast devices found")
            }
        } label: {
            Image(nsImage: model.castDevice == nil ? Theme.cast : Theme.castConnected)
                .renderingMode(.template)
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Cast")
    }

    private var selection: Binding<String?> {
        Binding {
            model.castDevice?.id
        } set: { id in
            model.cast(to: devices.first { $0.id == id })
        }
    }

    // A device can drop out of discovery while it is still the one playing.
    private var devices: [CastDevice] {
        guard let selected = model.castDevice, !model.castDevices.contains(where: { $0.id == selected.id }) else {
            return model.castDevices
        }
        return model.castDevices + [selected]
    }
}

struct AirPlayButton: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {}
}

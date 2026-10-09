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
    var logoSize: CGFloat = 30

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                controls
                if let track = model.currentTrack {
                    Text(track.line.uppercased())
                        .font(Theme.regular(15))
                        .lineLimit(1)
                        .help(track.line)
                        .padding(.leading, logoSize + 12)
                }
            }
            if let volume = model.castVolume {
                CastVolumeSlider(volume: volume)
            }
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Image(nsImage: Theme.logo)
                .resizable()
                .renderingMode(.template)
                .frame(width: logoSize, height: logoSize)
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

extension Track {
    var line: String { artist.isEmpty ? title : "\(artist) – \(title)" }
}

struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.bold(13))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .foregroundStyle(hovering ? .black : .white)
                .background(hovering ? .white : .black)
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

import NTSCore
import SwiftUI

struct WindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader(logoSize: 36)
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 16)
            Color.white.opacity(0.2).frame(height: 1)
            HStack(spacing: 0) {
                stations
                // Always there for a signed-in account, so the stations do not jump aside when the first track comes in.
                if model.account.email != nil {
                    Color.white.opacity(0.2).frame(width: 1)
                    TrackList()
                }
            }
            Color.white.opacity(0.2).frame(height: 1)
            HStack {
                Text("Unofficial app, not affiliated with NTS.")
                    .font(Theme.regular(13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 8)
                FooterButton(title: "Settings") { openWindow(id: NTSApp.settingsID) }
            }
            .padding(.leading, 28)
            .padding(.trailing, 22)
            .padding(.vertical, 8)
        }
        .frame(minWidth: model.account.email == nil ? 560 : 720, minHeight: 420)
        .background(.black)
        .ignoresSafeArea()
        .showsDockIconWhileOpen()
    }

    private var stations: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Live")
                HStack(alignment: .top, spacing: 16) {
                    ForEach(model.live) { StationTile(station: $0, aspectRatio: 16 / 9) }
                }
                if !model.mixtapes.isEmpty {
                    SectionLabel(title: "Infinite Mixtapes").padding(.top, 20)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                        ForEach(model.mixtapes) { StationTile(station: $0, aspectRatio: 1) }
                    }
                }
            }
            .padding(28)
        }
    }
}

private struct TrackList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(title: "Tracks")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                if model.tracks.isEmpty {
                    Text(note)
                        .font(Theme.regular(14))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 20)
                } else {
                    ForEach(model.tracks.prefix(10)) { track in
                        TrackRow(track: track, isCurrent: track.id == model.currentTrack?.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 28)
        }
        .frame(width: 250)
    }

    private var note: String {
        if model.tracksDenied { return "NTS shows its tracks to Supporters only, and this account is not one." }
        return model.playback == .stopped ? "Play a station to see its tracks." : "No tracks yet."
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            track.copy()
            copied = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // The time stays in place unseen, so the mark takes exactly its room.
                Text(track.start.formatted(date: .omitted, time: .shortened))
                    .font(Theme.regular(13))
                    .opacity(copied ? 0 : 0.5)
                    .frame(minWidth: 36, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if copied {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title.uppercased())
                        .font(Theme.bold(15))
                    if !track.artist.isEmpty {
                        Text(track.artist.uppercased())
                            .font(Theme.regular(14))
                            .opacity(0.7)
                    }
                }
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(hovering ? .black : .white)
            .background(hovering ? .white : .black)
            .overlay(alignment: .leading) {
                if isCurrent && !hovering {
                    Rectangle().fill(.white).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy \(track.line)")
        .task(id: copied) { await copied.clearsAfterAMoment { copied = false } }
    }
}

private struct StationTile: View {
    @Environment(AppModel.self) private var model
    let station: Station
    let aspectRatio: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            model.select(station)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Artwork(url: station.imageURL)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay(alignment: .bottomLeading) {
                        if let label = model.statusLabel(for: station) {
                            StatusBadge(label: label).padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.title.uppercased())
                        .font(Theme.bold(station.isLive ? 20 : 17))
                    Text((station.subtitle ?? " ").uppercased())
                        .font(Theme.regular(station.isLive ? 17 : 15))
                        .opacity(0.7)
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(hovering ? .black : .white)
            .background(hovering ? .white : .black)
            .overlay {
                if station.id == model.currentID {
                    Rectangle().strokeBorder(.white, lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

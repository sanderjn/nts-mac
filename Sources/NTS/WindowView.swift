import NTSCore
import SwiftUI

struct WindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader()
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 16)
            Color.white.opacity(0.2).frame(height: 1)
            HStack(spacing: 0) {
                stations
                // There for a signed-in account even without tracks, so the stations do not jump aside when the first one comes in.
                if showsTracks {
                    TracksEdge()
                    TrackList()
                }
            }
            Color.white.opacity(0.2).frame(height: 1)
            HStack(spacing: 0) {
                Text("Unofficial app, not affiliated with NTS.")
                    .font(Theme.regular(13))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.leading, 28)
                Spacer(minLength: 8)
                if model.account.email != nil {
                    Color.white.opacity(0.2).frame(width: 1)
                    BarButton {
                        model.setShowsTracks(!model.showsTracks)
                    } label: {
                        Image(nsImage: Theme.tracks)
                            .renderingMode(.template)
                            .opacity(model.showsTracks ? 1 : 0.4)
                    }
                    .help(model.showsTracks ? "Hide tracks" : "Show tracks")
                    .accessibilityLabel(model.showsTracks ? "Hide tracks" : "Show tracks")
                }
                Color.white.opacity(0.2).frame(width: 1)
                BarButton {
                    openURL(URL(string: "https://www.nts.live/supporters")!)
                } label: {
                    Text("SUPPORT NTS").font(Theme.bold(13))
                }
                Color.white.opacity(0.2).frame(width: 1)
                BarButton {
                    openWindow(id: NTSApp.settingsID)
                } label: {
                    Text("SETTINGS").font(Theme.bold(13))
                }
            }
            .frame(height: 34)
        }
        .frame(minWidth: showsTracks ? 470 + model.tracksWidth : 560, minHeight: 420)
        .background(.black)
        .ignoresSafeArea()
        .showsDockIconWhileOpen()
    }

    private var showsTracks: Bool {
        model.account.email != nil && model.showsTracks
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
        .frame(width: model.tracksWidth)
    }

    private var note: String {
        if model.tracksDenied { return "NTS shows its tracks to Supporters only, and this account is not one." }
        return model.playback == .stopped ? "Play a station to see its tracks." : "No tracks yet."
    }
}

/// The line between the stations and the tracks, which drags to make the tracks wider or narrower.
private struct TracksEdge: View {
    @Environment(AppModel.self) private var model
    @State private var widthAtStart: CGFloat?

    var body: some View {
        Color.white.opacity(0.2)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = widthAtStart ?? model.tracksWidth
                                widthAtStart = start
                                model.setTracksWidth(start - drag.translation.width)
                            }
                            .onEnded { _ in widthAtStart = nil }
                    )
            }
            // Above the track list, or that takes the half of the handle that lies over it.
            .zIndex(1)
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
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                // The time stays in place unseen, so the mark takes exactly its room.
                Text(track.start.formatted(date: .omitted, time: .shortened))
                    .font(Theme.regular(13))
                    .opacity(copied ? 0 : 0.5)
                    .overlay(alignment: .trailing) {
                        if isCurrent {
                            PlayingDot().offset(x: 14)
                        }
                    }
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
                            StatusBadge(label: label)
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
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(hovering || isCurrent ? .black : .white)
            .background(hovering || isCurrent ? .white : .black)
            .overlay {
                Rectangle().strokeBorder(.white.opacity(isCurrent ? 1 : 0.2), lineWidth: isCurrent ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var isCurrent: Bool {
        station.id == model.currentID
    }
}

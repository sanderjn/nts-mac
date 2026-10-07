import NTSCore
import SwiftUI

struct WindowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader(logoSize: 36)
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 16)
            Color.white.opacity(0.2).frame(height: 1)
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
        .frame(minWidth: 560, minHeight: 420)
        .background(.black)
        .ignoresSafeArea()
        .showsDockIconWhileOpen()
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

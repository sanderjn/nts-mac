import NTSCore
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            NowPlayingHeader()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            Color.white.opacity(0.2).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(title: "Live").padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                        ForEach(model.live) { StationRow(station: $0) }
                        if !model.mixtapes.isEmpty {
                            SectionLabel(title: "Infinite Mixtapes").padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
                            ForEach(model.mixtapes) { StationRow(station: $0) }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .onAppear { proxy.scrollTo(model.currentID, anchor: .center) }
            }
            .frame(height: 440)
            Color.white.opacity(0.2).frame(height: 1)
            HStack {
                FooterButton(title: "Open window") {
                    openWindow(id: NTSApp.windowID)
                    NSApp.activate()
                }
                FooterButton(title: "Settings") {
                    openWindow(id: NTSApp.settingsID)
                    NSApp.activate()
                }
                Spacer()
                FooterButton(title: "Quit") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
        .background(.black)
    }
}

private struct StationRow: View {
    @Environment(AppModel.self) private var model
    let station: Station
    @State private var hovering = false

    var body: some View {
        Button {
            model.select(station)
        } label: {
            HStack(spacing: 12) {
                Artwork(url: station.imageURL)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.title.uppercased())
                        .font(Theme.bold(16))
                    if let subtitle = station.subtitle {
                        Text(subtitle.uppercased())
                            .font(Theme.regular(14))
                            .opacity(0.7)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let label = model.statusLabel(for: station) {
                    Text(label.uppercased())
                        .font(Theme.bold(12))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(hovering ? .black : .white)
            .background(hovering ? .white : .black)
            .overlay(alignment: .leading) {
                if station.id == model.currentID {
                    Rectangle().fill(hovering ? .black : .white).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .id(station.id)
    }
}

private struct FooterButton: View {
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

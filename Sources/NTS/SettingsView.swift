import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(Theme.bold(18))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
            Color.white.opacity(0.2).frame(height: 1)
            SectionLabel(title: "General").padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
            SettingToggle(
                title: "Launch at login",
                detail: "Start NTS in the menu bar when you log in.",
                isOn: Binding { model.launchesAtLogin } set: { model.setLaunchesAtLogin($0) }
            )
            SectionLabel(title: "Play on").padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
            SettingToggle(
                title: "Google Cast",
                detail: "Show the Cast button and look for devices on your network.",
                isOn: Binding { model.showsCast } set: { model.setShowsCast($0) }
            )
            SettingToggle(
                title: "AirPlay",
                detail: "Show the AirPlay button.",
                isOn: Binding { model.showsAirPlay } set: { model.setShowsAirPlay($0) }
            )
            Text("Version \(version). Unofficial app, not affiliated with NTS.")
                .font(Theme.regular(13))
                .opacity(0.5)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
        .frame(width: 380)
        .background(Color.black.ignoresSafeArea())
        .showsDockIconWhileOpen()
        .onAppear { model.refreshLaunchesAtLogin() }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(Theme.bold(16))
                Text(detail)
                    .font(Theme.regular(14))
                    .opacity(0.7)
            }
        }
        .toggleStyle(BadgeToggleStyle(hovering: hovering))
        .onHover { hovering = $0 }
    }
}

/// A full-width row that inverts on hover like the station rows, with the state as a badge.
private struct BadgeToggleStyle: ToggleStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                Text(configuration.isOn ? "ON" : "OFF")
                    .font(Theme.bold(12))
                    .foregroundStyle(configuration.isOn != hovering ? .black : .white)
                    .frame(width: 34, height: 20)
                    .background(configuration.isOn ? (hovering ? .black : .white) : .clear)
                    .overlay { Rectangle().strokeBorder(hovering ? .black : .white, lineWidth: 1) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .foregroundStyle(hovering ? .black : .white)
            .background(hovering ? .white : .black)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

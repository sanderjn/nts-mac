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
            SectionLabel(title: "NTS account").padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
            AccountSection()
                .padding(.horizontal, 20)
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

private struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        let account = model.account
        VStack(alignment: .leading, spacing: 10) {
            if let signedIn = account.email {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signedIn)
                            .font(Theme.bold(16))
                            .lineLimit(1)
                        Text(model.tracksDenied
                            ? "NTS shows its tracks to Supporters only, and this account is not one."
                            : "The track that plays shows under the show.")
                            .font(Theme.regular(14))
                            .opacity(0.7)
                    }
                    Spacer(minLength: 8)
                    OutlineButton(title: "Sign out", action: account.signOut)
                }
            } else {
                Text("Sign in to see which track is playing. NTS shows its tracks to Supporters only.")
                    .font(Theme.regular(14))
                    .opacity(0.7)
                TextField("", text: $email, prompt: Text("Email").foregroundStyle(.white.opacity(0.4)))
                    .textContentType(.username)
                    .modifier(FieldStyle())
                SecureField("", text: $password, prompt: Text("Password").foregroundStyle(.white.opacity(0.4)))
                    .textContentType(.password)
                    .modifier(FieldStyle())
                    .onSubmit(signIn)
                HStack(spacing: 12) {
                    OutlineButton(title: account.isSigningIn ? "Signing in" : "Sign in", action: signIn)
                        .disabled(account.isSigningIn || email.isEmpty || password.isEmpty)
                    Text("Your password goes to NTS and is not saved.")
                        .font(Theme.regular(13))
                        .opacity(0.5)
                }
            }
            if let problem = account.problem {
                Text(problem)
                    .font(Theme.bold(14))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task {
            await model.account.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            if model.account.email != nil {
                email = ""
                password = ""
            }
        }
    }
}

private struct FieldStyle: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.regular(16))
            .foregroundStyle(.white)
            .tint(.white)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay { Rectangle().strokeBorder(.white.opacity(focused ? 1 : 0.4), lineWidth: 1) }
    }
}

private struct OutlineButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Theme.bold(13))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(hovering && isEnabled ? .black : .white)
                .background(hovering && isEnabled ? .white : .black)
                .overlay { Rectangle().strokeBorder(.white, lineWidth: 1) }
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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

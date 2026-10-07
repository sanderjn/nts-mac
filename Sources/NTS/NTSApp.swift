import SwiftUI

@main
struct NTSApp: App {
    static let windowID = "main"
    static let settingsID = "settings"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Theme.registerFonts()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("NTS", id: Self.windowID) {
            WindowView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 880, height: 680)
        .commands {
            CommandGroup(replacing: .appSettings) { SettingsCommand() }
        }

        Window("NTS Settings", id: Self.settingsID) {
            SettingsView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            Image(nsImage: Theme.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct SettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: NTSApp.settingsID) }
            .keyboardShortcut(",")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started by the login item, the app stays in the menu bar instead of putting its window on screen.
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard event?.eventID == kAEOpenApplication,
              event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem else { return }
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(NTSApp.windowID) == true {
                window.close()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

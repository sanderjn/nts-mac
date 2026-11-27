import Foundation
import NTSCore

let arguments = Array(CommandLine.arguments.dropFirst())
let target = arguments.first
let volumeOnly = arguments.dropFirst().first == "volume"
let seconds = volumeOnly ? 3 : arguments.dropFirst().first.flatMap(Double.init) ?? 12

let browser = CastBrowser()
var session: CastSession?

browser.onChange = { devices in
    guard let target else {
        print(devices.map { "\($0.name)\($0.hasDisplay ? " (display)" : "")" })
        return
    }
    guard session == nil, let device = devices.first(where: { $0.name == target }) else { return }
    let started = Date.now
    let casting = CastSession(device: device)
    casting.onStatusChange = { print(String(format: "%5.1fs", -started.timeIntervalSinceNow), $0) }
    casting.onVolumeChange = { print(String(format: "%5.1fs", -started.timeIntervalSinceNow), "volume", $0.map { "\($0)" } ?? "none") }
    if volumeOnly {
        casting.connect()
        if let level = arguments.dropFirst(2).first.flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                casting.setVolume(level)
            }
        }
    } else {
        casting.play(LiveStations.all[0].castMedia)
    }
    session = casting
    Task {
        try? await Task.sleep(for: .seconds(seconds))
        casting.close(stoppingReceiver: !volumeOnly)
        try? await Task.sleep(for: .seconds(1))
        exit(0)
    }
}
browser.start()

Task {
    try? await Task.sleep(for: .seconds(target == nil ? 3 : seconds + 10))
    exit(target == nil || session != nil ? 0 : 1)
}
RunLoop.main.run()

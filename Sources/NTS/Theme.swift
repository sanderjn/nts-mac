import AppKit
import SwiftUI

@MainActor
enum Theme {
    static func registerFonts() {
        for name in [regularName, boldName] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        // A typeface of your own takes the place of the bundled one: Regular.ttf and Bold.ttf in Application Support/NTS/Fonts.
        let fonts = URL.applicationSupportDirectory.appending(path: "NTS/Fonts")
        guard let regular = register(fonts.appending(path: "Regular.ttf")),
              let bold = register(fonts.appending(path: "Bold.ttf")) else { return }
        regularName = regular
        boldName = bold
    }

    private static var regularName = "ArchivoNarrow-Regular"
    private static var boldName = "ArchivoNarrow-Bold"

    private static func register(_ url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return name
    }

    static func regular(_ size: CGFloat) -> Font {
        .custom(regularName, fixedSize: size)
    }

    static func bold(_ size: CGFloat) -> Font {
        .custom(boldName, fixedSize: size)
    }

    static let red = Color(red: 232 / 255, green: 23 / 255, blue: 23 / 255)

    static let logo = templateImage("Logo", size: 26, fallback: "radio")
    static let menuBarIcon = templateImage("Logo", size: 18, fallback: "radio")
    static let tracks = templateImage("Tracks", size: 24, fallback: "music.note.list")
    static let cast = templateImage("Cast", size: 20, fallback: "tv")
    static let castConnected = templateImage("CastConnected", size: 20, fallback: "tv.fill")

    /// The system spinner drawn by hand, one image per step: a menu bar label only shows images.
    static let menuBarSpinner: [NSImage] = (0..<spokes).map { step in
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            for spoke in 0..<spokes {
                let angle = .pi / 2 - CGFloat(spoke) / CGFloat(spokes) * 2 * .pi
                let path = NSBezierPath()
                path.move(to: NSPoint(x: rect.midX + cos(angle) * 3.5, y: rect.midY + sin(angle) * 3.5))
                path.line(to: NSPoint(x: rect.midX + cos(angle) * 7.5, y: rect.midY + sin(angle) * 7.5))
                path.lineWidth = 1.8
                path.lineCapStyle = .round
                let age = CGFloat((step - spoke + spokes) % spokes) / CGFloat(spokes)
                NSColor.black.withAlphaComponent(1 - age * 0.85).setStroke()
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let spokes = 8

    private static func templateImage(_ name: String, size: CGFloat, fallback: String) -> NSImage {
        let image = Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: name)!
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}

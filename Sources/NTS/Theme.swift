import AppKit
import SwiftUI

@MainActor
enum Theme {
    static func registerFonts() {
        for name in ["ArchivoNarrow-Regular", "ArchivoNarrow-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func regular(_ size: CGFloat) -> Font {
        .custom("ArchivoNarrow-Regular", fixedSize: size)
    }

    static func bold(_ size: CGFloat) -> Font {
        .custom("ArchivoNarrow-Bold", fixedSize: size)
    }

    static let logo = templateImage("Logo", size: 26, fallback: "radio")
    static let menuBarIcon = templateImage("Logo", size: 18, fallback: "radio")
    static let cast = templateImage("Cast", size: 20, fallback: "tv")
    static let castConnected = templateImage("CastConnected", size: 20, fallback: "tv.fill")

    private static func templateImage(_ name: String, size: CGFloat, fallback: String) -> NSImage {
        let image = Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: name)!
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}

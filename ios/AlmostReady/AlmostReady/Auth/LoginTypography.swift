import CoreText
import Foundation
import SwiftUI

enum LoginTypography {
    private static let regularFace = register("Inter-Regular")
    private static let boldFace = register("Inter-Bold")

    static func regular(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(regularFace, size: size, relativeTo: style)
    }

    static func bold(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(boldFace, size: size, relativeTo: style)
    }

    private static func register(_ name: String) -> String {
        // Register only when the login screen needs the font.
        if let url = Bundle.main.url(forResource: name, withExtension: "otf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return name
    }
}

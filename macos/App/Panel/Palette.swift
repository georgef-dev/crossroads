// The colors an event, card or reminder is drawn in.
//
// CrossroadsCore decides which shade a kind gets; this turns that choice into
// a color. The idea is Omarchy's: each tag has a color, a flagged row is
// filled with a wash of it, and anything unflagged stays quiet. Omarchy takes
// its two colors from the shell theme, where work is simply the foreground
// color. The Mac gives work a hue of its own instead, so a glance separates
// the two without reading anything.
//
// Every color is defined for light and dark, because the panel sits on a
// material that follows the system.

import AppKit
import SwiftUI

import CrossroadsCore

extension Color {
    /// One color with a value for each appearance, so it follows the system.
    init(light: Int, dark: Int) {
        self = Color(
            nsColor: NSColor(name: nil) { appearance in
                let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: Double((hex >> 16) & 0xFF) / 255,
                    green: Double((hex >> 8) & 0xFF) / 255,
                    blue: Double(hex & 0xFF) / 255,
                    alpha: 1
                )
            }
        )
    }
}

enum Palette {
    /// Personal is blue, work is violet: far enough apart to tell at a glance,
    /// close enough in weight that neither shouts.
    static let personal = Color(light: 0x2F6FED, dark: 0x7AA2F7)
    static let work = Color(light: 0x7C4DD0, dark: 0xBB9AF7)
    /// Something is wrong, or a reminder is late.
    static let urgent = Color(light: 0xC2410C, dark: 0xFF9E64)
    static let ok = Color(light: 0x15803D, dark: 0x9ECE6A)

    static func base(_ tag: Tag) -> Color {
        tag == .work ? work : personal
    }

    /// The flat color for a tag and kind: its tag's color, a quieter shade when
    /// it overlaps its own tag, and the midpoint of both when personal meets
    /// work.
    static func color(tag: Tag, kind: Kind) -> Color {
        switch shade(kind) {
        case .blend: Color(light: 0x5A5EDE, dark: 0x9B9EF7)
        case .darker: base(tag).opacity(0.7)
        case .plain: base(tag)
        }
    }

    /// Personal meeting work is the one thing worth drawing as two colors, so
    /// a clash reads as a clash rather than as another colored row.
    static func stripe(tag: Tag, kind: Kind) -> LinearGradient {
        let colors: [Color] = kind == .mixed
            ? [personal, work]
            : [color(tag: tag, kind: kind), color(tag: tag, kind: kind)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// The wash behind a flagged row. Omarchy uses the tag color at 0.18.
    static func wash(tag: Tag, kind: Kind) -> Color {
        color(tag: tag, kind: kind).opacity(0.16)
    }

    /// A stable color per sender, so the same person keeps the same initial.
    static func forSender(_ name: String) -> Color {
        let hues = [
            Color(light: 0x2F6FED, dark: 0x7AA2F7),
            Color(light: 0x7C4DD0, dark: 0xBB9AF7),
            Color(light: 0x0E7490, dark: 0x2AC3DE),
            Color(light: 0xB45309, dark: 0xE0AF68),
            Color(light: 0x15803D, dark: 0x9ECE6A),
            Color(light: 0xBE185D, dark: 0xF7768E),
        ]
        let seed = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return hues[seed % hues.count]
    }
}

// The colors an event or card is drawn in. CrossroadsCore decides which shade
// a kind gets; this turns that choice into a color.

import SwiftUI

import CrossroadsCore

enum Palette {
    static let personal = Color(red: 0.478, green: 0.635, blue: 0.969)
    static let work = Color(red: 0.878, green: 0.686, blue: 0.408)

    static func base(_ tag: Tag) -> Color {
        tag == .work ? work : personal
    }

    /// Its tag's color, a darker shade of it when it overlaps its own tag, or a
    /// blend of both tags when personal meets work.
    static func color(tag: Tag, kind: Kind) -> Color {
        switch shade(kind) {
        case .blend:
            return blended
        case .darker:
            return base(tag).opacity(0.65)
        case .plain:
            return base(tag)
        }
    }

    private static let blended = Color(
        red: (0.478 + 0.878) / 2,
        green: (0.635 + 0.686) / 2,
        blue: (0.969 + 0.408) / 2
    )
}

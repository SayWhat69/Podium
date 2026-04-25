import SwiftUI

extension Color {
    /// Creates a `Color` from a hex integer, e.g. `Color(hex: 0x1f2937)`.
    init(hex: Int, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:     Double((hex >> 16) & 0xff) / 255,
            green:   Double((hex >> 08) & 0xff) / 255,
            blue:    Double((hex >> 00) & 0xff) / 255,
            opacity: opacity
        )
    }
}

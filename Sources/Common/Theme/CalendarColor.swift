import SwiftUI
import UIKit

enum CalendarColor {
    static let defaultEventHex = 0xFF8FBDF5
    static let copyModeAccent = Color(red: 0.0, green: 0.85, blue: 0.92)
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    /// Matches Android ColorPicker pastel presets
    static let pastelPresets: [Int] = [
        0xFFE59494, // pastel red
        0xFF8FBDF5, // pastel blue
        0xFF99C79B, // pastel green
        0xFF7BD6E0, // pastel cyan
        0xFFFFDF82, // pastel yellow
        0xFFEF8DAB, // pastel pink
        0xFFB786C7, // pastel lilac
        0xFFFFBF80, // pastel orange
        0xFFA1938E, // muted brown
        0xFF9CA8AD, // blue gray
        0xFFDEE396  // pastel lime
    ]

    static let compactPresets: [Int] = Array(pastelPresets.prefix(5))

    static let presetColors: [Int] = pastelPresets

    static func opaqueHex(_ hex: Int) -> Int {
        (hex & 0x00FFFFFF) | 0xFF000000
    }

    static func hex(from color: Color) -> Int {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return defaultEventHex
        }

        let r = Int((red.clamped(to: 0...1) * 255).rounded())
        let g = Int((green.clamped(to: 0...1) * 255).rounded())
        let b = Int((blue.clamped(to: 0...1) * 255).rounded())
        return 0xFF000000 | (r << 16) | (g << 8) | b
    }
}

extension Color {
    init(calendarHex hex: Int) {
        let alpha = Double((hex >> 24) & 0xFF) / 255.0
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha == 0 ? 1.0 : alpha)
    }
}

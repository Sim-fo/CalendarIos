import SwiftUI
import UIKit

enum CalendarColor {
    static let defaultEventHex = 0xFF3A7AFE
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    static let presetColors: [Int] = [
        0xFF3A7AFE,
        0xFF11A36A,
        0xFFEF6C3E,
        0xFFD44C8D,
        0xFF6B58D6
    ]
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

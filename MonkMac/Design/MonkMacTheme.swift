import SwiftUI

enum MonkMacTheme {
    static let accent = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.60, blue: 0.92),
            Color(red: 0.47, green: 0.34, blue: 0.88),
            Color(red: 0.02, green: 0.67, blue: 0.58)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let background = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.05, blue: 0.20),
            Color(red: 0.13, green: 0.09, blue: 0.30),
            Color(red: 0.05, green: 0.28, blue: 0.45),
            Color(red: 0.03, green: 0.47, blue: 0.50)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let action = accent
}

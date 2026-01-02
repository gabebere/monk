import UIKit

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
    }
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
    }
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func moodSoft() {
        impact(style: .soft, intensity: 0.35)
    }

    static func moodMedium() {
        impact(style: .light, intensity: 0.6)
    }

    static func moodStrong() {
        impact(style: .heavy, intensity: 0.9)
    }

    private static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred(intensity: intensity)
    }
}

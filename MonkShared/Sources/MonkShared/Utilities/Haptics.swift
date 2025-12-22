import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum Haptics {
    #if canImport(UIKit)
    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
    }
    public static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8)
    }
    public static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
    }
    public static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public static func moodSoft() {
        impact(style: .soft, intensity: 0.35)
    }

    public static func moodMedium() {
        impact(style: .light, intensity: 0.6)
    }

    public static func moodStrong() {
        impact(style: .heavy, intensity: 0.9)
    }

    private static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred(intensity: intensity)
    }
    #elseif canImport(AppKit)
    public static func light() { performGeneric() }
    public static func medium() { performGeneric() }
    public static func heavy() { performGeneric() }
    public static func soft() { performGeneric() }
    public static func success() { performGeneric() }
    public static func warning() { performGeneric() }
    public static func moodSoft() { performGeneric() }
    public static func moodMedium() { performGeneric() }
    public static func moodStrong() { performGeneric() }

    private static func performGeneric() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
    #else
    public static func light() {}
    public static func medium() {}
    public static func heavy() {}
    public static func soft() {}
    public static func success() {}
    public static func warning() {}
    public static func moodSoft() {}
    public static func moodMedium() {}
    public static func moodStrong() {}
    #endif
}

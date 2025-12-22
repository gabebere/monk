import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// A lightweight confetti emitter using CAEmitterLayer.
// Emits colorful shapes for a short duration, then stops automatically.
#if canImport(UIKit)
public struct ConfettiView: UIViewRepresentable {
    public var duration: TimeInterval = 1.6

    public init(duration: TimeInterval = 1.6) {
        self.duration = duration
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 1)
        emitter.beginTime = CACurrentMediaTime()

        var cells: [CAEmitterCell] = []
        let colors: [UIColor] = [
            UIColor.systemPink, UIColor.systemTeal, UIColor.systemYellow,
            UIColor.systemBlue, UIColor.systemGreen, UIColor.systemOrange,
            UIColor.systemPurple
        ]

        for color in colors {
            let cell = CAEmitterCell()
            // Sparser and faster
            cell.birthRate = 8
            cell.lifetime = 1.5
            cell.lifetimeRange = 0.6
            cell.velocity = 300
            cell.velocityRange = 120
            cell.yAcceleration = 220
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 4
            cell.spin = 3.5
            cell.spinRange = 4.0
            cell.scale = 0.45
            cell.scaleRange = 0.2
            cell.contents = ConfettiView.makeConfettiImage(color: color).cgImage
            cells.append(cell)
        }

        emitter.emitterCells = cells
        view.layer.addSublayer(emitter)

        // Stop emission after duration and remove later
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            emitter.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                emitter.removeFromSuperlayer()
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private static func makeConfettiImage(color: UIColor, size: CGSize = CGSize(width: 8, height: 12)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            // Draw a rounded rectangle for variety
            color.setFill()
            let rectPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height), cornerRadius: 2)
            rectPath.fill()
        }
    }
}
#elseif canImport(AppKit)
public struct ConfettiView: NSViewRepresentable {
    public var duration: TimeInterval = 1.6

    public init(duration: TimeInterval = 1.6) {
        self.duration = duration
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let emitter = CAEmitterLayer()
        let width = NSScreen.main?.frame.width ?? 800
        emitter.emitterPosition = CGPoint(x: width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: width, height: 1)
        emitter.beginTime = CACurrentMediaTime()

        var cells: [CAEmitterCell] = []
        let colors: [NSColor] = [
            NSColor.systemPink, NSColor.systemTeal, NSColor.systemYellow,
            NSColor.systemBlue, NSColor.systemGreen, NSColor.systemOrange,
            NSColor.systemPurple
        ]

        for color in colors {
            let cell = CAEmitterCell()
            cell.birthRate = 8
            cell.lifetime = 1.5
            cell.lifetimeRange = 0.6
            cell.velocity = 300
            cell.velocityRange = 120
            cell.yAcceleration = 220
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 4
            cell.spin = 3.5
            cell.spinRange = 4.0
            cell.scale = 0.45
            cell.scaleRange = 0.2
            cell.contents = ConfettiView.makeConfettiImage(color: color).cgImage
            cells.append(cell)
        }

        emitter.emitterCells = cells
        view.layer?.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            emitter.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                emitter.removeFromSuperlayer()
            }
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func makeConfettiImage(color: NSColor, size: CGSize = CGSize(width: 8, height: 12)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        color.setFill()
        let rectPath = NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 2, yRadius: 2)
        rectPath.fill()
        return image
    }
}
#endif

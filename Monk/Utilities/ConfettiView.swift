import SwiftUI
import UIKit

// A lightweight confetti emitter using CAEmitterLayer.
// Emits colorful shapes for a short duration, then stops automatically.
struct ConfettiView: UIViewRepresentable {
    var duration: TimeInterval = 1.6

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
        return renderer.image { ctx in
            // Draw a rotated rectangle + circle combo for variety
            color.setFill()
            let rectPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height), cornerRadius: 2)
            rectPath.fill()
        }
    }
}

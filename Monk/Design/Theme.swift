import SwiftUI

enum Theme {
    // Warm Aurora palette and components
    static func background() -> some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.22), // deep indigo base
                Color(red: 0.16, green: 0.20, blue: 0.40), // indigo
                Color(red: 0.06, green: 0.42, blue: 0.50), // teal
                Color(red: 0.28, green: 0.31, blue: 0.70)  // soft violet/indigo
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var buttonGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.18, green: 0.58, blue: 0.85), // blue
            Color(red: 0.03, green: 0.64, blue: 0.60)  // teal
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var haloGradient: LinearGradient {
        LinearGradient(colors: [
            Color.cyan.opacity(0.45),
            Color.blue.opacity(0.35),
            Color.purple.opacity(0.35)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var cardStroke: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var textPrimary: Color { Color.white.opacity(0.95) }
}

struct AnimatingBackground: View {
    @State private var driftRight = false
    var body: some View {
        ZStack {
            Theme.background()
                .ignoresSafeArea()
                .overlay(
                    // A large blurred diagonal gradient drifting slowly for depth
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Theme.haloGradient)
                        .frame(width: UIScreen.main.bounds.width * 1.8,
                               height: UIScreen.main.bounds.height * 1.2)
                        .rotationEffect(.degrees(0))
                        .offset(x: driftRight ? 60 : -60, y: 0)
                        .blur(radius: 110)
                        .opacity(0.18)
                        .animation(.easeInOut(duration: 24).repeatForever(autoreverses: true), value: driftRight)
                        .onAppear { driftRight = true }
                )
        }
    }
}

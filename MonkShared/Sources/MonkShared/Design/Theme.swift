import SwiftUI

public enum Theme {
    // MARK: - Gradient palettes

    public static func homeBackground() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.07, blue: 0.26),
                Color(red: 0.19, green: 0.12, blue: 0.38),
                Color(red: 0.08, green: 0.36, blue: 0.58),
                Color(red: 0.05, green: 0.58, blue: 0.62)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public static func background() -> LinearGradient { homeBackground() }

    public static func dataBackground() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.14, blue: 0.24),
                Color(red: 0.09, green: 0.26, blue: 0.46),
                Color(red: 0.18, green: 0.38, blue: 0.62),
                Color(red: 0.30, green: 0.46, blue: 0.78)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public static func historyBackground() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.08, blue: 0.12),
                Color(red: 0.33, green: 0.13, blue: 0.20),
                Color(red: 0.46, green: 0.24, blue: 0.19),
                Color(red: 0.58, green: 0.36, blue: 0.18)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public static func settingsBackground() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.12, blue: 0.18),
                Color(red: 0.14, green: 0.18, blue: 0.28),
                Color(red: 0.20, green: 0.24, blue: 0.36),
                Color(red: 0.28, green: 0.32, blue: 0.44)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    public static var buttonGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.18, green: 0.58, blue: 0.85), // blue
            Color(red: 0.03, green: 0.64, blue: 0.60)  // teal
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var homeHaloGradient: LinearGradient {
        LinearGradient(colors: [
            Color.cyan.opacity(0.45),
            Color.teal.opacity(0.32),
            Color.purple.opacity(0.30)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var haloGradient: LinearGradient { homeHaloGradient }

    public static var dataHaloGradient: LinearGradient {
        LinearGradient(colors: [
            Color.cyan.opacity(0.35),
            Color.blue.opacity(0.30),
            Color.indigo.opacity(0.35)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var historyHaloGradient: LinearGradient {
        LinearGradient(colors: [
            Color.orange.opacity(0.40),
            Color.pink.opacity(0.32),
            Color.red.opacity(0.28)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var settingsHaloGradient: LinearGradient {
        LinearGradient(colors: [
            Color.blue.opacity(0.30),
            Color.cyan.opacity(0.26),
            Color.purple.opacity(0.28)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var cardStroke: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    public static var textPrimary: Color { Color.white.opacity(0.95) }
}

public struct AnimatingBackground: View {
    public var base: LinearGradient = Theme.background()
    public var halo: LinearGradient = Theme.haloGradient
    @State private var driftRight = false

    public init(base: LinearGradient = Theme.background(),
                halo: LinearGradient = Theme.haloGradient) {
        self.base = base
        self.halo = halo
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                base
                    .ignoresSafeArea()
                    .overlay(
                        // A large blurred diagonal gradient drifting slowly for depth
                        RoundedRectangle(cornerRadius: 0)
                            .fill(halo)
                            .frame(width: proxy.size.width * 1.8,
                                   height: proxy.size.height * 1.2)
                            .rotationEffect(.degrees(0))
                            .offset(x: driftRight ? 60 : -60, y: 0)
                            .blur(radius: 110)
                            .opacity(0.18)
                            .animation(.easeInOut(duration: 24).repeatForever(autoreverses: true), value: driftRight)
                            .onAppear { driftRight = true }
                    )
            }
            .ignoresSafeArea()
        }
    }
}

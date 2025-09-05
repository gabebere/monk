import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @EnvironmentObject private var focus: FocusManager
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [Preferences]
    private var prefs: Preferences {
        if let p = prefsList.first { return p }
        let p = Preferences()
        modelContext.insert(p)
        return p
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AnimatingBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        TimerCard()
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal)
                    .padding(.top, 100)
                }
            }
            .navigationTitle("Welcome to Monk.")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle(isOn: Binding(
                            get: { prefs.discardShortSessions ?? false },
                            set: { newVal in
                                prefs.discardShortSessions = newVal
                                try? modelContext.save()
                                if newVal { focus.purgeShortSessionsIfNeeded() }
                            }
                        )) {
                            Label("Discard sessions under 2 min", systemImage: "scissors")
                        }
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Options")
                }
            }
        }
    }
  
    private func firstName() -> String {
        let raw = UIDevice.current.name
        let normalized = raw.replacingOccurrences(of: "’", with: "'")
        if let range = normalized.range(of: "'s ") {
            let before = String(normalized[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = before.split(separator: " ").first, !first.isEmpty {
                return String(first)
            }
        }
        if let first = normalized.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return "there"
    }
}

private struct TimerCard: View {
    @EnvironmentObject private var focus: FocusManager
    @State private var outerAngle: Double = -30
    @State private var innerAngle: Double = 30
    @State private var driftX: CGFloat = 0
    @State private var driftY: CGFloat = 0
    @Namespace private var focusAnim
    @State private var rippleOpacity: Double = 0
    @State private var rippleScale: CGFloat = 1
    @State private var pressDown: Bool = false
    @State private var outerLoopTask: Task<Void, Never>? = nil
    @State private var innerLoopTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 20) {
            if focus.currentSession == nil {
                // Idle: inviting button with refined elliptical glow centered around button
                Button(action: animateStartAndBeginSession) {
                    ZStack {
                        // Ripple effect behind the button text
                        Capsule()
                            .fill(Theme.buttonGradient)
                            .opacity(rippleOpacity)
                            .scaleEffect(rippleScale)
                            .blur(radius: 20)
                            .animation(.easeOut(duration: 0.6), value: rippleOpacity)
                            .animation(.easeOut(duration: 0.6), value: rippleScale)

                        Text("Time to focus?")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 16)
                            .background(
                                Capsule().fill(Theme.buttonGradient)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    .blendMode(.overlay)
                            )
                            .shadow(color: Color.cyan.opacity(0.5), radius: 36, x: 0, y: 10)
                            .shadow(color: Color.blue.opacity(0.35), radius: 54, x: 0, y: 0)
                            .scaleEffect(pressDown ? 0.96 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: pressDown)
                    }
                }
                .accessibilityLabel("Start focusing")
                // Draw glows behind without affecting layout (so button sits near top)
                .background(
                    ZStack {
                        // Outer elliptical glow (slower, wider)
                        Ellipse()
                            .fill(AngularGradient(colors: [
                                Color.cyan.opacity(0.8),
                                Color.blue.opacity(0.7),
                                Color.purple.opacity(0.75),
                                Color.cyan.opacity(0.8)
                            ], center: .center))
                            .frame(width: 180, height: 120)
                            .blur(radius: 16)
                            .rotationEffect(.degrees(outerAngle))
                            .opacity(0.7)
                            .offset(x: driftX, y: driftY)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .onAppear {
                                withAnimation(.none) {
                                    outerAngle = -30
                                    driftX = 0
                                    driftY = 0
                                }
                                startOuterLoop()
                            }
                            .onDisappear { outerLoopTask?.cancel(); outerLoopTask = nil }

                        // Inner elliptical glow (faster, tighter, counter-rotating)
                        Ellipse()
                            .fill(AngularGradient(colors: [
                                Color.purple.opacity(0.9),
                                Color.blue.opacity(0.75),
                                Color.cyan.opacity(0.85),
                                Color.purple.opacity(0.9)
                            ], center: .center))
                            .frame(width: 150, height: 100)
                            .blur(radius: 10)
                            .rotationEffect(.degrees(innerAngle))
                            .opacity(0.8)
                            .offset(x: -driftX * 0.83, y: -driftY * 0.75)
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .onAppear {
                                withAnimation(.none) { innerAngle = 30 }
                                startInnerLoop()
                            }
                            .onDisappear { innerLoopTask?.cancel(); innerLoopTask = nil }
                        }
                )
                .padding(.top, 0)
                .transition(.focusElegant)
            } else {
                // Active timer typography and controls
                VStack(spacing: 12) {
                    Text(elapsedString())
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .kerning(0.5)
                        .foregroundColor(Theme.textPrimary)
                        .accessibilityLabel("Elapsed time")

                    Label("In session", systemImage: "smallcircle.fill.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(Theme.buttonGradient)
                            .frame(width: 110, height: 110)
                            .blur(radius: 20)
                            .opacity(0.5)

                        Button(action: stopSession) {
                            ZStack {
                                Circle()
                                    .fill(Theme.buttonGradient)
                                    .frame(width: 92, height: 92)
                                    .shadow(color: Color.cyan.opacity(0.45), radius: 22, x: 0, y: 10)
                                    .shadow(color: Color.blue.opacity(0.35), radius: 36, x: 0, y: 0)
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        .accessibilityLabel("Stop")
                    }
                    .padding(.bottom, 0)
                }
                .offset(y: -60)
                .transition(.focusElegant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: focus.currentSession != nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func startSession() { focus.start() }
    private func stopSession() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { focus.stop() }
    }

    private func animateStartAndBeginSession() {
        // Press down tap feedback
        pressDown = true
        // Ripple: flash then expand and fade
        rippleOpacity = 0.55
        rippleScale = 1.0
        withAnimation(.easeOut(duration: 0.6)) {
            rippleOpacity = 0.0
            rippleScale = 2.2
        }
        // Trigger session start within a spring animation to match geometry morph
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                startSession()
            }
            // Release the press scale shortly after
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                pressDown = false
                rippleScale = 1.0
            }
        }
    }

    private func elapsedString() -> String {
        guard let start = focus.currentSession?.startedAt else { return "00:00:00" }
        let elapsed = Date().timeIntervalSince(start)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Ellipse rotation loops
    private func startOuterLoop() {
        outerLoopTask?.cancel()
        outerLoopTask = Task { @MainActor in
            let seg: UInt64 = 1_200_000_000 // 1.2s per segment (slower)
            while !Task.isCancelled {
                withAnimation(.linear(duration: 1.2)) { outerAngle = 30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { outerAngle = -30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { outerAngle = 30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { outerAngle = -30 }
                try? await Task.sleep(nanoseconds: seg)
                // Return to rest near the button and pause, then continue smoothly (no snap reset)
                withAnimation(.linear(duration: 0.9)) { outerAngle = 0 }
                try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s pause
            }
        }
    }

    private func startInnerLoop() {
        innerLoopTask?.cancel()
        innerLoopTask = Task { @MainActor in
            let seg: UInt64 = 1_200_000_000 // 1.2s per segment (slower)
            // synchronized start with outer loop (no initial offset)
            while !Task.isCancelled {
                withAnimation(.linear(duration: 1.2)) { innerAngle = -30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { innerAngle = 30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { innerAngle = -30 }
                try? await Task.sleep(nanoseconds: seg)
                withAnimation(.linear(duration: 1.2)) { innerAngle = 30 }
                try? await Task.sleep(nanoseconds: seg)
                // Return to rest and pause, then continue smoothly (no snap reset)
                withAnimation(.linear(duration: 0.9)) { innerAngle = 0 }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }
}

// MARK: - Elegant transition for swapping CTA and timer
private struct FocusAnimModifier: ViewModifier {
    enum Phase { case insert, remove, identity }
    let phase: Phase
    func body(content: Content) -> some View {
        switch phase {
        case .insert:
            content.opacity(0).scaleEffect(0.96).offset(y: 14)
        case .remove:
            content.opacity(0).scaleEffect(0.96).offset(y: -14)
        case .identity:
            content
        }
    }
}

private extension AnyTransition {
    static var focusElegant: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FocusAnimModifier(phase: .insert),
                                 identity: FocusAnimModifier(phase: .identity)),
            removal: .modifier(active: FocusAnimModifier(phase: .remove),
                               identity: FocusAnimModifier(phase: .identity))
        )
    }
}

private struct TagChip: View {
    let title: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "xmark.circle.fill")
                .onTapGesture { onRemove() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
    }
}

private struct TagEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: FocusSession
    var onStop: () -> Void
    
    @State private var newTag: String = ""
    @State private var localNote: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Session Complete!")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Add tags and notes to help categorize your focus session")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Form {
                    Section("Note") {
                        TextField("What did you focus on?", text: $localNote, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                    }
                    
                    Section("Tags") {
                        HStack {
                            TextField("Add tag (e.g., work, study)", text: $newTag)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Add") { addTag() }
                                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        if !session.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(session.tags, id: \.self) { tag in
                                        TagChip(title: "#\(tag)") {
                                            removeTag(tag)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Add Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveAndFinish()
                    }
                    .disabled(session.tags.isEmpty && localNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            localNote = session.note ?? ""
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !session.tags.contains(trimmed) {
            session.tags.append(trimmed)
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        session.tags.removeAll { $0 == tag }
    }

    private func saveAndFinish() {
        session.note = localNote.trimmingCharacters(in: .whitespacesAndNewlines)
        onStop()
        dismiss()
    }
}

private struct TodayTotal: View {
    @EnvironmentObject private var focus: FocusManager
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let hours = focus.todayTotalSeconds / 3600
        HStack {
            Image(systemName: "calendar")
            Text("Today: ")
            Text(String(format: "%.2f h", hours)).bold().fontDesign(.monospaced)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThickMaterial))
        .foregroundStyle(colorScheme == .light ? .black : .primary)
    }
}

// RecentSessionsView removed per design simplification

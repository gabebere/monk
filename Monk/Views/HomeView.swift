import SwiftUI
import SwiftData

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
        ZStack(alignment: .top) {
            AnimatingBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    TimerCard()
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal)
                .padding(.top, 64)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("Welcome to Monk.")
        .navigationBarTitleDisplayMode(.large)
    }
  
}

private struct TimerCard: View {
    @EnvironmentObject private var focus: FocusManager
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsList: [Preferences]
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
    @State private var showStopDetails: Bool = false
    @State private var stoppedSession: FocusSession? = nil

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
                            // Animation loops controlled centrally via onChange/task

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
                            // Animation loops controlled centrally via onChange/task
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

                    // Removed secondary status label as requested

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
                .transition(.focusElegant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: focus.currentSession != nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .sheet(isPresented: $showStopDetails) {
            if let session = stoppedSession {
                TagEntryView(session: session) {
                    // No-op: stop already occurred
                }
            }
        }
        .task {
            if focus.currentSession == nil { restartIdleAnimation() }
        }
        .onChange(of: focus.currentSession == nil) { _, isIdle in
            if isIdle {
                restartIdleAnimation()
            } else {
                outerLoopTask?.cancel(); outerLoopTask = nil
                innerLoopTask?.cancel(); innerLoopTask = nil
            }
        }
    }

    private func startSession() { focus.start() }
    private func stopSession() {
        // Capture the session reference before it ends (and possibly gets deleted if too short)
        let session = focus.currentSession
        let startTime = session?.startedAt
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            focus.stop()
        }
        if let s = session, let start = startTime {
            let discardShort = prefsList.first?.discardShortSessions == true
            let duration = Date().timeIntervalSince(start)
            let willDiscard = discardShort && duration < 120
            if !willDiscard {
                stoppedSession = s
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showStopDetails = true }
            }
        }
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
    private func restartIdleAnimation() {
        outerLoopTask?.cancel(); outerLoopTask = nil
        innerLoopTask?.cancel(); innerLoopTask = nil
        withAnimation(.none) {
            outerAngle = -30
            innerAngle = 30
        }
        startOuterLoop()
        startInnerLoop()
    }
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
                // Continuous loop without rest
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
                // Continuous loop without rest
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: FocusSession
    var onStop: () -> Void
    
    @State private var newTag: String = ""
    @State private var moodValue: Int = 1
    @State private var allTags: [String] = []

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    Text("Session Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(congratulationText())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Form {
                        tagSection
                        feelingsSection
                    }
                    
                    Spacer()
                }
                // Confetti overlay (fires on appear, then stops automatically)
                ConfettiView(duration: 2.0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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
                }
            }
        }
        .onAppear {
            moodValue = session.moodScore ?? 1
            loadAllTags()
        }
    }

    // MARK: - Subviews (split to help type-checker)
    @ViewBuilder
    private var tagSection: some View {
        Section("What did you do?") {
            HStack(alignment: .firstTextBaseline) {
                ZStack(alignment: .leading) {
                    TextField("Add tag (e.g., work, study)", text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { addFromSubmit() }
                    if let suffix = autocompleteSuffix, !suffix.isEmpty {
                        HStack(spacing: 0) {
                            Text(newTag).opacity(0)
                            Text(suffix).foregroundStyle(.secondary)
                        }
                        .allowsHitTesting(false)
                    }
                }
                Button("Add") { addTag() }
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            tagsChipsView
        }
    }

    @ViewBuilder
    private var feelingsSection: some View {
        Section("How was this session?") {
            MoodSlider(value: $moodValue)
        }
    }

    @ViewBuilder
    private var suggestionsView: some View {
        let suggestions = matchingSuggestions
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(action: { newTag = suggestion }) {
                            Text("#\(suggestion)")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use tag \(suggestion)")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var tagsChipsView: some View {
        let tags = session.tags
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(title: "#\(tag)") { removeTag(tag) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // Inline autocomplete suffix for the first matching suggestion
    private var autocompleteSuffix: String? {
        let prefix = normalizeTag(newTag)
        guard !prefix.isEmpty, let suggestion = matchingSuggestions.first else { return nil }
        guard suggestion.hasPrefix(prefix) else { return nil }
        let dropCount = prefix.count
        if suggestion.count > dropCount {
            return String(suggestion.dropFirst(dropCount))
        }
        return nil
    }

    private func addTag() {
        let norm = normalizeTag(newTag)
        guard !norm.isEmpty else { return }
        if !session.tags.contains(where: { normalizeTag($0) == norm }) {
            session.tags.append(norm)
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        let norm = normalizeTag(tag)
        session.tags.removeAll { normalizeTag($0) == norm }
    }

    private func saveAndFinish() {
        session.moodScore = moodValue
        try? modelContext.save()
        onStop()
        dismiss()
    }

    // MARK: - Suggestions
    private var matchingSuggestions: [String] {
        let prefix = normalizeTag(newTag)
        guard !prefix.isEmpty else { return [] }
        let existing = Set(session.tags.map { normalizeTag($0) })
        return allTags
            .filter { $0.hasPrefix(prefix) && !existing.contains($0) }
            .sorted()
            .prefix(8)
            .map { $0 }
    }
    private func loadAllTags() {
        let all = (try? modelContext.fetch(FetchDescriptor<FocusSession>())) ?? []
        let set = Set(all.flatMap { $0.tags.map(normalizeTag) })
        allTags = Array(set).sorted()
    }
    private func addFromSubmit() {
        if let first = matchingSuggestions.first {
            newTag = first
        }
        addTag()
    }
    private func normalizeTag(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    // MARK: - Congrats message
    private func congratulationText(now: Date = .now) -> String {
        let start = session.startedAt
        let end = session.endedAt ?? now
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 1 {
            let hoursPart = hours == 1 ? "1 hour" : "\(hours) hours"
            let minutesPart = minutes > 0 ? " and \(minutes) \(minutes == 1 ? "minute" : "minutes")" : ""
            return "Well done! You have focused for \(hoursPart)\(minutesPart)."
        } else {
            return "Well done! You have focused for \(minutes) \(minutes == 1 ? "minute" : "minutes")."
        }
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

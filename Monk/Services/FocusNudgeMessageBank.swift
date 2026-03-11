import Foundation

enum FocusNudgeMessageBank {
    private static let titles: [String] = [
        "Good morning. Ready to focus?",
        "How about a quick focus block?",
        "Midday check-in",
        "Afternoon momentum",
        "Keep the flow alive",
        "Close the day with focus"
    ]

    // 6 slots × 5 messages = 30 total nudges.
    private static let messagesBySlot: [[String]] = [
        [
            "Start small. One focused block can set the tone for your day.",
            "Morning focus now can make the rest of the day easier.",
            "You are at the start line. Want to begin a deep-work sprint?",
            "A clean morning session can unlock momentum. Begin now?",
            "Your first focus session is waiting."
        ],
        [
            "Two focused hours can change your whole day. Start one now?",
            "Quick check: ready for your next focus block?",
            "You still have a wide-open window. Want to use it well?",
            "A short focused sprint right now can compound later.",
            "How about locking in one meaningful session?"
        ],
        [
            "Midday is a great reset point. Ready for focused work?",
            "What matters most this afternoon? Start with one focus block.",
            "Your focus rhythm can restart right here. Begin now?",
            "Take midday back with one intentional session.",
            "A focused block now can recover the day."
        ],
        [
            "Afternoon check-in: want to get one deep session in?",
            "You still have time for meaningful progress. Start focusing?",
            "One focused push this afternoon can move things forward.",
            "If your day drifted, this is your reset moment.",
            "Try one focused sprint before the late day rush."
        ],
        [
            "Late day can still be productive. Start one focus block?",
            "Protect this hour and finish a meaningful chunk.",
            "You are close to a strong day. Want one more session?",
            "A focused late-day sprint can close open loops.",
            "Momentum is still available. Start now?"
        ],
        [
            "Last stretch. Want to end today with focused work?",
            "Close strong with one intentional focus session.",
            "Even one short session now can improve today’s score.",
            "Before you wrap up, try one final deep-work block.",
            "Finish the day on purpose. Start focusing now?"
        ]
    ]

    static func title(for slotIndex: Int) -> String {
        guard titles.indices.contains(slotIndex) else { return "Time to focus" }
        return titles[slotIndex]
    }

    static func message(forSlot slotIndex: Int, day: Date, calendar: Calendar) -> String {
        guard messagesBySlot.indices.contains(slotIndex) else {
            return "Ready to start a focus session?"
        }
        let slotMessages = messagesBySlot[slotIndex]
        guard !slotMessages.isEmpty else { return "Ready to start a focus session?" }

        let seed = daySeed(for: day, calendar: calendar)
        let offset = slotIndex * 31
        let index = abs(seed + offset) % slotMessages.count
        return slotMessages[index]
    }

    private static func daySeed(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return (year * 10_000) + (month * 100) + day
    }
}

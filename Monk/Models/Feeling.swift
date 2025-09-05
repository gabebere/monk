import Foundation

struct FeelingOption: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
}

enum FeelingsCatalog {
    static let all: [FeelingOption] = [
        .init(id: "accomplished", emoji: "🎯", title: "Accomplished – satisfaction from making progress."),
        .init(id: "motivated", emoji: "🚀", title: "Motivated – inspired to keep going."),
        .init(id: "engaged", emoji: "🔥", title: "Engaged – mentally stimulated, in the flow."),
        .init(id: "confident", emoji: "💪", title: "Confident – reassured by understanding or progress."),
        .init(id: "reflective", emoji: "🤔", title: "Reflective – thinking about what was just learned or done."),
        .init(id: "distracted", emoji: "🙃", title: "Distracted – noticing attention wander."),
        .init(id: "restless", emoji: "🏃‍♂️", title: "Restless – wanting a change of pace."),
        .init(id: "indifferent", emoji: "😐", title: "Indifferent – neither strongly satisfied nor tired."),
        .init(id: "numb", emoji: "😶", title: "Numb – going through motions without much feeling."),
        .init(id: "tired", emoji: "😴", title: "Tired – mentally or physically fatigued."),
        .init(id: "overwhelmed", emoji: "😵‍💫", title: "Overwhelmed – too much information or work."),
        .init(id: "frustrated", emoji: "😤", title: "Frustrated – stuck on a difficult problem."),
        .init(id: "anxious", emoji: "😬", title: "Anxious – worried about deadlines or performance."),
        .init(id: "bored", emoji: "🥱", title: "Bored – disengaged from the task."),
        .init(id: "stressed", emoji: "😖", title: "Stressed – tense from pressure or difficulty."),
        .init(id: "burntout", emoji: "🥵", title: "Burnt‑out – drained from prolonged effort."),
        .init(id: "hungry_thirsty", emoji: "🥤", title: "Hungry / Thirsty – realizing basic needs."),
        .init(id: "stiff", emoji: "🧍‍♂️", title: "Stiff – body tension from sitting still."),
        .init(id: "headache_eyes", emoji: "🤕", title: "Headache / Eye strain – screens, posture."),
        .init(id: "alert", emoji: "☕️", title: "Alert / Awake – task was stimulating."),
        .init(id: "relaxed", emoji: "😌", title: "Relaxed – focused and smooth.")
    ]
}

import Foundation

struct InsightsDashboardModel {
    let hero: HeroModel
    let bestWindow: InsightCardModel
    let rhythm: TodayRhythmModel
    let momentum: InsightCardModel
    let followThrough: InsightCardModel
    let bottom: BottomSectionModel
}

struct HeroModel {
    let focusedTodayText: String
    let totalWithMonkText: String
    let calmLaneText: String?
    let calmLaneWindow: CalmLaneWindow?
}

struct CalmLaneWindow {
    let startHour: Int
    let endHour: Int
}

struct InsightCardModel {
    let title: String
    let headline: String
    let subheadline: String
    let actionHint: String
}

struct TodayRhythmModel {
    let title: String
    let hourlyMinutes: [Int] // exactly 24 items
    let headline: String
    let actionHint: String
}

enum BottomSectionModel {
    case weeklyPace(WeeklyPaceModel)
    case consistency(ConsistencySnapshotModel)
}

struct WeeklyPaceModel {
    let title: String
    let headline: String
    let subheadline: String
    let actionHint: String
}

struct ConsistencySnapshotModel {
    let title: String
    let headline: String
    let subheadline: String
    let actionHint: String
}

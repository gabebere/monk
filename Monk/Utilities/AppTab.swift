enum AppTab: Int, CaseIterable, Hashable {
    case home
    case insights
    case history
    case settings

    var index: Int { rawValue }
}

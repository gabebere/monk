enum AppTab: Int, CaseIterable, Hashable {
    case home
    case projects
    case history
    case settings

    var index: Int { rawValue }
}

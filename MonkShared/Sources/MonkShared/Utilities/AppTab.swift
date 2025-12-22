public enum AppTab: Int, CaseIterable, Hashable {
    case home
    case insights
    case history
    case settings

    public var index: Int { rawValue }
}

enum FocusCommandField: Hashable {
    case intention
    case hours
    case minutes
    case applications
    case websites

    static let navigationOrder: [FocusCommandField] = [
        .intention,
        .hours,
        .minutes,
        .applications,
        .websites
    ]
}

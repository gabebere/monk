import Foundation

enum FocusCommitmentStartError: LocalizedError {
    case alreadyActive
    case browserSelectionRequired
    case invalidDuration
    case permissionDenied
    case selectionEncodingFailed

    var errorDescription: String? {
        switch self {
        case .alreadyActive:
            "A focus is already active. It must finish before another can begin."
        case .browserSelectionRequired:
            "Choose at least one browser to open your allowed websites."
        case .invalidDuration:
            "Choose a focus duration greater than zero."
        case .permissionDenied:
            "Monk needs Screen Time access to block apps and websites."
        case .selectionEncodingFailed:
            "Monk could not securely save this app selection."
        }
    }
}

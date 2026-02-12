import Foundation
import FamilyControls
import ManagedSettings

enum ManagedAppTokenCodec {
    static func encodeSelection(from tokens: Set<ManagedSettings.ApplicationToken>) -> Data? {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = tokens
        return try? JSONEncoder().encode(selection)
    }

    static func decodeSelectionTokens(from data: Data?) -> Set<ManagedSettings.ApplicationToken> {
        guard let data,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return [] }
        return selection.applicationTokens
    }

    static func encodeToken(_ token: ManagedSettings.ApplicationToken) -> Data? {
        try? JSONEncoder().encode(token)
    }

    static func tokenIdentifier(_ token: ManagedSettings.ApplicationToken) -> String {
        if let data = encodeToken(token) {
            return data.base64EncodedString()
        }
        return String(token.hashValue)
    }
}

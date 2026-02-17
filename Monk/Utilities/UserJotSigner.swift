import Foundation
import CryptoKit

enum UserJotSigner {
    private static let infoPlistSecretKey = "USERJOT_IDENTITY_SECRET"
    private static let environmentSecretKey = "USERJOT_IDENTITY_SECRET"

    static func signature(for userId: String) -> String? {
        guard let secret = loadSecret() else { return nil }
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(userId.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadSecret() -> String? {
        if let envSecret = ProcessInfo.processInfo.environment[environmentSecretKey],
           !envSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envSecret
        }

        if let plistSecret = Bundle.main.object(forInfoDictionaryKey: infoPlistSecretKey) as? String,
           !plistSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plistSecret
        }

        return nil
    }
}

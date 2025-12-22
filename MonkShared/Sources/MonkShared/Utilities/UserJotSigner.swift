import Foundation
import CryptoKit

public enum UserJotSigner {
    // WARNING: Keeping secrets in-app is not secure. Provided per request to unblock SSO tests.
    private static let secret = "sk_0bcq5u0sz7n9cldxhdo33wsj5ss1kgxw"

    public static func signature(for userId: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(userId.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

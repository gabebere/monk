import Foundation
import OSLog

actor WelcomeEmailService {
    static let shared = WelcomeEmailService()

    private let logger = Logger(subsystem: "com.gbr.Monk", category: "WelcomeEmailService")
    private let sentUsersKey = "welcome_email.sent_user_ids"
    private let webhookURLOverrideKey = "welcome.webhook.url"
    private let webhookURLInfoPlistKey = "WELCOME_WEBHOOK_URL"

    func sendWelcomeIfNeeded(userID: String,
                             email: String?,
                             firstName: String?,
                             provider: String,
                             isFirstSeenOnDevice: Bool) async {
        guard !userID.isEmpty else { return }
        guard let normalizedEmail = email?.trimmedNonEmpty else {
            Analytics.track("welcome_email_skipped", [
                "reason": "missing_email",
                "provider": provider,
                "is_first_seen_on_device": isFirstSeenOnDevice
            ])
            return
        }
        guard !hasSentWelcome(for: userID) else { return }
        guard let endpoint = webhookURL() else {
            Analytics.track("welcome_email_skipped", [
                "reason": "missing_webhook_url",
                "provider": provider,
                "is_first_seen_on_device": isFirstSeenOnDevice
            ])
            return
        }

        let payload = WelcomeEmailPayload(
            userId: userID,
            email: normalizedEmail,
            firstName: firstName?.trimmedNonEmpty,
            provider: provider,
            isFirstSeenOnDevice: isFirstSeenOnDevice,
            signedInAt: Date(),
            appVersion: appVersionString(),
            platform: "ios"
        )

        do {
            let body = try JSONEncoder.welcomeEmail.encode(payload)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Analytics.track("welcome_email_failed", [
                    "reason": "invalid_response",
                    "provider": provider
                ])
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                Analytics.track("welcome_email_failed", [
                    "reason": "http_error",
                    "status_code": httpResponse.statusCode,
                    "provider": provider
                ])
                return
            }

            markWelcomeSent(for: userID)
            Analytics.track("welcome_email_enqueued", [
                "provider": provider,
                "is_first_seen_on_device": isFirstSeenOnDevice
            ])
        } catch {
            logger.error("Welcome email webhook failed: \(error.localizedDescription, privacy: .public)")
            Analytics.track("welcome_email_failed", [
                "reason": "request_error",
                "provider": provider
            ])
        }
    }
}

private extension WelcomeEmailService {
    func hasSentWelcome(for userID: String) -> Bool {
        let users = Set(UserDefaults.standard.stringArray(forKey: sentUsersKey) ?? [])
        return users.contains(userID)
    }

    func markWelcomeSent(for userID: String) {
        var users = Set(UserDefaults.standard.stringArray(forKey: sentUsersKey) ?? [])
        users.insert(userID)
        UserDefaults.standard.set(Array(users).sorted(), forKey: sentUsersKey)
    }

    func webhookURL() -> URL? {
        if let overridden = UserDefaults.standard.string(forKey: webhookURLOverrideKey)?.trimmedNonEmpty,
           let url = URL(string: overridden),
           url.scheme?.hasPrefix("http") == true {
            return url
        }

        if let configured = Bundle.main.object(forInfoDictionaryKey: webhookURLInfoPlistKey) as? String,
           let normalized = configured.trimmedNonEmpty,
           let url = URL(string: normalized),
           url.scheme?.hasPrefix("http") == true {
            return url
        }
        return nil
    }

    func appVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}

private struct WelcomeEmailPayload: Encodable {
    let userId: String
    let email: String
    let firstName: String?
    let provider: String
    let isFirstSeenOnDevice: Bool
    let signedInAt: Date
    let appVersion: String
    let platform: String
}

private extension JSONEncoder {
    static var welcomeEmail: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

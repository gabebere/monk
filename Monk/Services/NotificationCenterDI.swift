import Foundation
import UserNotifications

protocol UserNotificationCenterType {
    func getAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(options: UNAuthorizationOptions, completionHandler: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, withCompletionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenterType {
    func getAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        self.getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }
}


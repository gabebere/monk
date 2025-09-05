import Foundation

protocol LiveActivityControllerType {
    func start(startedAt: Date)
    func end()
}

struct SystemLiveActivityController: LiveActivityControllerType {
    func start(startedAt: Date) {
        if #available(iOS 16.1, *), NSClassFromString("ActivityKit.Activity") != nil {
            LiveActivityManager.start(startedAt: startedAt)
        }
    }
    func end() {
        if #available(iOS 16.1, *), NSClassFromString("ActivityKit.Activity") != nil {
            LiveActivityManager.end()
        }
    }
}


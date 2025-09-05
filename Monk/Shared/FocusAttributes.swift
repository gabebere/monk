import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct FocusAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var startedAt: Date
        public init(startedAt: Date) { self.startedAt = startedAt }
    }

    public init() {}
}
#endif


import SwiftUI
import WidgetKit

@main
struct MonkWidgets: WidgetBundle {
    var body: some Widget {
        MonkSummaryWidget()
        #if canImport(ActivityKit)
        MonkLiveActivityWidget()
        #endif
    }
}


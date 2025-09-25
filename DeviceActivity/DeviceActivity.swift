//
//  DeviceActivity.swift
//  DeviceActivity
//
//  Created by Gabriel Berezovsky on 22/09/25.
//

import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct DeviceActivity: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Create a report for each DeviceActivityReport.Context that your app supports.
        TotalActivityReport { totalActivity in
            TotalActivityView(totalActivity: totalActivity)
        }
        // Add more reports here...
    }
}

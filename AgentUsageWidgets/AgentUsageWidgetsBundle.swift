//
//  AgentUsageWidgetsBundle.swift
//  AgentUsageWidgets
//

import SwiftUI
import WidgetKit

@main
struct AgentUsageWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AgentUsageWidgets()
        AgentUsageLockScreenWidget()
        AgentUsageWidgetsLiveActivity()
    }
}

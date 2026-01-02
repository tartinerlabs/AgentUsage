//
//  ClaudeMeterWidgetsBundle.swift
//  ClaudeMeterWidgets
//

import SwiftUI
import WidgetKit

@main
struct ClaudeMeterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClaudeMeterWidgets()
        ClaudeMeterLockScreenWidget()
        ClaudeMeterWidgetsLiveActivity()
    }
}

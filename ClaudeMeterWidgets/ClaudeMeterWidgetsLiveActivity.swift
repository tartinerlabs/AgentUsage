//
//  ClaudeMeterWidgetsLiveActivity.swift
//  ClaudeMeterWidgets
//
//  Created by Ru Chern Chong on 2/1/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ClaudeMeterWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ClaudeMeterWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudeMeterWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ClaudeMeterWidgetsAttributes {
    fileprivate static var preview: ClaudeMeterWidgetsAttributes {
        ClaudeMeterWidgetsAttributes(name: "World")
    }
}

extension ClaudeMeterWidgetsAttributes.ContentState {
    fileprivate static var smiley: ClaudeMeterWidgetsAttributes.ContentState {
        ClaudeMeterWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ClaudeMeterWidgetsAttributes.ContentState {
         ClaudeMeterWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ClaudeMeterWidgetsAttributes.preview) {
   ClaudeMeterWidgetsLiveActivity()
} contentStates: {
    ClaudeMeterWidgetsAttributes.ContentState.smiley
    ClaudeMeterWidgetsAttributes.ContentState.starEyes
}

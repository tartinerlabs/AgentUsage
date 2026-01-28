# Platform-Specific Features

## macOS Menu Bar Apps

### MenuBarExtra

```swift
@main
struct MyApp: App {
    @State private var viewModel = ViewModel()

    var body: some Scene {
        // Menu bar with popover window
        MenuBarExtra {
            PopoverView()
                .environment(viewModel)
        } label: {
            // Status item label - can be Image or Text
            Image(systemName: viewModel.statusIcon)
        }
        .menuBarExtraStyle(.window) // Popover style

        // Optional: Main window
        Window("Settings", id: "settings") {
            SettingsView()
                .environment(viewModel)
        }
    }
}
```

### Menu Style (Dropdown)

```swift
MenuBarExtra("MyApp", systemImage: "star") {
    Button("Action 1") { }
    Button("Action 2") { }
    Divider()
    Button("Quit") { NSApplication.shared.terminate(nil) }
}
.menuBarExtraStyle(.menu)
```

### Hide Dock Icon

In `Info.plist`:
```xml
<key>LSUIElement</key>
<true/>
```

Or in Xcode: Target > Info > "Application is agent (UIElement)" = YES

### Known Issue: SettingsLink (2025)

`SettingsLink` doesn't work reliably in `MenuBarExtra`. Menu bar apps are "second-class citizens" in SwiftUI:
- No dock icon (uses `.accessory` activation policy)
- Not in app switcher
- Windows may appear behind other apps

**Workaround:** Open settings manually with activation policy juggling:

```swift
func openSettings() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // Open settings window via Window id
}
```

### Dynamic Dock Icon

Show dock icon only when window is open:

```swift
@main
struct MyApp: App {
    @State private var showDockIcon = false

    var body: some Scene {
        Window("Main", id: "main") {
            ContentView()
                .onAppear { setDockIconVisible(true) }
                .onDisappear { setDockIconVisible(false) }
        }
    }

    private func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
```

## Launch at Login

Using SMAppService (macOS 13+):

```swift
import ServiceManagement

final class LaunchAtLoginService {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

Usage in Settings:

```swift
struct SettingsView: View {
    @State private var launchAtLogin = false
    private let service = LaunchAtLoginService()

    var body: some View {
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onAppear { launchAtLogin = service.isEnabled }
            .onChange(of: launchAtLogin) { _, newValue in
                try? service.setEnabled(newValue)
            }
    }
}
```

## Sparkle Auto-Updates (macOS)

### Setup

1. Add Sparkle package: `https://github.com/sparkle-project/Sparkle`
2. Add to Info.plist:
   - `SUFeedURL`: URL to appcast.xml
   - `SUPublicEDKey`: EdDSA public key

### UpdaterController

```swift
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    private let updater: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updater.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updater.checkForUpdates(nil)
    }
}
```

## iOS Widgets (WidgetKit)

**Important:** WidgetKit only supports SwiftUI views. UIKit is not allowed.

### Refresh Budget

Widgets have a limited refresh budget:
- **40-70 refreshes per day** in production
- Roughly **every 15-60 minutes**
- Budget varies by how often widget is visible

**Best practices:**
- Populate timelines with as many future entries as possible
- Use `.after(date)` policy for predictable refresh times
- Use `.never` and manually call `reloadTimelines(ofKind:)` for event-driven updates

### TimelineProvider

```swift
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now, data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: .now, data: loadData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: .now, data: loadData())
        // Refresh in 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}
```

### Widget Definition

```swift
@main
struct MyWidget: Widget {
    let kind = "MyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("My Widget")
        .description("Shows important info")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

### Widget Sizes

```swift
struct MyWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: Provider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(data: entry.data)
        case .systemMedium:
            MediumView(data: entry.data)
        case .systemLarge:
            LargeView(data: entry.data)
        default:
            SmallView(data: entry.data)
        }
    }
}
```

### App Group Data Sharing

```swift
// In main app - write data
let defaults = UserDefaults(suiteName: "group.com.example.myapp")
defaults?.set(encodedData, forKey: "widgetData")
WidgetCenter.shared.reloadTimelines(ofKind: "MyWidget")

// In widget - read data
func loadData() -> WidgetData {
    let defaults = UserDefaults(suiteName: "group.com.example.myapp")
    guard let data = defaults?.data(forKey: "widgetData") else {
        return .placeholder
    }
    return try? JSONDecoder().decode(WidgetData.self, from: data) ?? .placeholder
}
```

## Live Activities (iOS)

### ActivityAttributes

```swift
import ActivityKit

struct MyActivityAttributes: ActivityAttributes {
    // Static data - doesn't change during activity
    let title: String

    // Dynamic data - updates during activity
    struct ContentState: Codable, Hashable {
        let progress: Double
        let status: String
    }
}
```

### Info.plist

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

### Push Notification Updates (iOS 17.2+)

Live Activities can be started and updated via push notifications:

```swift
// Get push token when starting activity
currentActivity = try Activity.request(
    attributes: attributes,
    content: .init(state: state, staleDate: nil),
    pushType: .token  // Enable push updates
)

// Listen for token updates
for await tokenData in currentActivity.pushTokenUpdates {
    let token = tokenData.map { String(format: "%02x", $0) }.joined()
    // Send token to your server
}
```

**Notification budget:**
- Use priority 5 for non-urgent updates (budget-friendly)
- Use priority 10 for critical updates
- Enable `NSSupportsLiveActivitiesFrequentUpdates` for high-frequency use cases

### Live Activity Manager

```swift
actor LiveActivityManager {
    private var currentActivity: Activity<MyActivityAttributes>?

    func start(title: String, progress: Double) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = MyActivityAttributes(title: title)
        let state = MyActivityAttributes.ContentState(
            progress: progress,
            status: "In Progress"
        )

        currentActivity = try Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(progress: Double, status: String) async {
        let state = MyActivityAttributes.ContentState(
            progress: progress,
            status: status
        )
        await currentActivity?.update(
            ActivityContent(state: state, staleDate: nil)
        )
    }

    func end() async {
        await currentActivity?.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
    }
}
```

### Live Activity Widget

```swift
struct MyActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MyActivityAttributes.self) { context in
            // Lock Screen view
            LockScreenView(
                title: context.attributes.title,
                state: context.state
            )
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                }
            } compactLeading: {
                Image(systemName: "star")
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
            } minimal: {
                Image(systemName: "star")
            }
        }
    }
}
```

## Lock Screen Widgets (iOS)

```swift
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreen", provider: Provider()) { entry in
            LockScreenView(entry: entry)
        }
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "star")
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.title)
                ProgressView(value: entry.progress)
            }

        case .accessoryInline:
            Text("\(entry.title): \(Int(entry.progress * 100))%")

        default:
            EmptyView()
        }
    }
}
```

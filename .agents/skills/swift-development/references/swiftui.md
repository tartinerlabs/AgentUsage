# SwiftUI Reference

## @Observable (Swift 5.9+)

Replaces `ObservableObject` + `@Published`. No Combine needed.

```swift
@Observable
final class ViewModel {
    var items: [Item] = []        // Automatically observed
    var isLoading = false         // Automatically observed
    private var cache: [String: Data] = [:] // Private still observed

    func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await fetchItems()
    }
}
```

### With MainActor

```swift
@Observable @MainActor
final class ViewModel {
    var data: [Item] = []

    func refresh() async {
        data = await service.fetch()
    }
}
```

## Dependency Injection

### @Environment (Recommended)

```swift
// 1. Create observable model
@Observable @MainActor
final class AppState {
    var user: User?
    var theme: Theme = .system
}

// 2. Inject at app level
@main
struct MyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}

// 3. Access in any child view
struct ProfileView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let user = appState.user {
            Text(user.name)
        }
    }
}
```

### @Bindable for Two-Way Binding

When you need to bind to @Observable properties:

```swift
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Toggle("Dark Mode", isOn: $state.isDarkMode)
            Picker("Theme", selection: $state.theme) {
                ForEach(Theme.allCases) { theme in
                    Text(theme.name).tag(theme)
                }
            }
        }
    }
}
```

### Multiple Models

```swift
@main
struct MyApp: App {
    @State private var viewModel = ViewModel()
    @State private var settings = SettingsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(settings)
        }
    }
}
```

## View Composition

### Extract Subviews

```swift
struct ItemListView: View {
    @Environment(ViewModel.self) private var viewModel

    var body: some View {
        List(viewModel.items) { item in
            ItemRow(item: item)
        }
    }
}

// Subview - receives data, not environment
struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack {
            Text(item.name)
            Spacer()
            Text(item.date, style: .date)
        }
    }
}
```

### ViewBuilder for Conditional Content

```swift
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack {
            content()
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// Usage
Card {
    if showDetails {
        DetailView()
    } else {
        SummaryView()
    }
}
```

## Async Patterns

### .task Modifier

```swift
struct ContentView: View {
    @Environment(ViewModel.self) private var viewModel

    var body: some View {
        List(viewModel.items) { item in
            ItemRow(item: item)
        }
        .task {
            // Runs when view appears
            // Automatically cancelled when view disappears
            await viewModel.load()
        }
        .task(id: viewModel.filter) {
            // Re-runs when filter changes
            await viewModel.search()
        }
    }
}
```

### .refreshable

```swift
List(viewModel.items) { item in
    ItemRow(item: item)
}
.refreshable {
    await viewModel.refresh()
}
```

## State Management

### @State for Local View State

```swift
struct CounterView: View {
    @State private var count = 0

    var body: some View {
        Button("Count: \(count)") {
            count += 1
        }
    }
}
```

### @State for Reference Types (Observable)

```swift
struct ParentView: View {
    @State private var viewModel = ViewModel()

    var body: some View {
        ChildView()
            .environment(viewModel)
    }
}
```

### @Binding for Child Mutation

```swift
struct ParentView: View {
    @State private var isPresented = false

    var body: some View {
        Button("Show") { isPresented = true }
            .sheet(isPresented: $isPresented) {
                SheetView(isPresented: $isPresented)
            }
    }
}

struct SheetView: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button("Dismiss") { isPresented = false }
    }
}
```

## MVVM Architecture

```swift
// Model
struct Item: Identifiable, Codable {
    let id: UUID
    var name: String
    var isComplete: Bool
}

// ViewModel
@Observable @MainActor
final class ItemListViewModel {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?

    private let service: ItemService

    init(service: ItemService = ItemService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await service.fetchItems()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleComplete(_ item: Item) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isComplete.toggle()
        try? await service.update(items[index])
    }
}

// View
struct ItemListView: View {
    @Environment(ItemListViewModel.self) private var viewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else {
                List(viewModel.items) { item in
                    ItemRow(item: item) {
                        Task { await viewModel.toggleComplete(item) }
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

## Navigation

### NavigationStack (iOS 16+)

```swift
struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List(items) { item in
                NavigationLink(value: item) {
                    Text(item.name)
                }
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
        }
    }
}
```

### TabView

```swift
struct MainView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}
```

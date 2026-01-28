---
name: swift-development
description: Swift and SwiftUI development patterns including concurrency (actors, async/await, Sendable), SwiftUI (MVVM, @Observable, @Environment), SwiftData persistence (@Model, @ModelActor), and platform features (menu bar apps, widgets, Live Activities). Use when writing Swift code, building SwiftUI apps, implementing actors or async code, working with SwiftData, or developing macOS/iOS features.
---

# Swift Development Skill

Modern Swift patterns for macOS 15+ and iOS 18+ development.

## Quick Patterns

### Actor with MainActor ViewModel

```swift
// Thread-safe service
actor APIService {
    func fetch() async throws -> Data { ... }
}

// UI-bound ViewModel
@Observable @MainActor
final class MyViewModel {
    var data: [Item] = []
    private let service = APIService()

    func load() async {
        data = try? await service.fetch()
    }
}

// View injection
@main struct MyApp: App {
    @State private var viewModel = MyViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(viewModel)
        }
    }
}
```

### SwiftData Model

```swift
@Model
final class Item {
    @Attribute(.unique) var id: String
    var name: String
    var createdAt: Date

    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.createdAt = .now
    }
}
```

### Async Task in View

```swift
struct ContentView: View {
    @Environment(MyViewModel.self) private var viewModel

    var body: some View {
        List(viewModel.data) { item in ... }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
    }
}
```

## When to Read References

Read the appropriate reference file for detailed patterns and examples:

| Topic | Reference File |
|-------|----------------|
| `actor`, `@MainActor`, `Sendable`, `Task` | [references/concurrency.md](references/concurrency.md) |
| `@Observable`, `@Environment`, `@Bindable`, MVVM | [references/swiftui.md](references/swiftui.md) |
| `@Model`, `@ModelActor`, `@Query`, predicates | [references/swiftdata.md](references/swiftdata.md) |
| Menu bar apps, widgets, Live Activities, Launch at Login | [references/platforms.md](references/platforms.md) |
| `@Test`, `#expect`, async testing, mocks | [references/testing.md](references/testing.md) |

## Style Guide

Follow [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):

- **Clarity at point of use** - Names should read naturally at call sites
- **Prefer methods over free functions** - `x.distance(to: y)` not `distance(x, y)`
- **Name booleans** as assertions: `isEmpty`, `hasContent`, `canSubmit`
- **Mutating vs non-mutating**: `x.sort()` mutates, `x.sorted()` returns new
- **Protocols**: capabilities use `-able`/`-ible` (Equatable), roles are nouns (Collection)

## Common Pitfalls

1. **Don't block MainActor** - Use `Task { }` for async work, not `Task.detached`
2. **Actors are reference types** - They isolate state, not copy it
3. **`@Observable` replaces `@Published`** - No `@StateObject` needed in modern SwiftUI
4. **SwiftData `@Model` is a macro** - It generates `Sendable` conformance automatically
5. **Widget timelines are budgeted** - Request updates sparingly (~40-70 per day)

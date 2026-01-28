# Swift Concurrency Reference

## Swift 6.2 Approachable Concurrency

Swift 6.2 introduces "Approachable Concurrency" - progressive disclosure where you only learn as much concurrency as you use:

```swift
// New: @concurrent for explicit parallel execution
@concurrent
func heavyComputation() async -> Result {
    // Runs outside caller's actor context
}

// New projects default to implicit @MainActor on app code
// Existing projects can opt-in via build settings
```

**Key changes:**
- Async functions now run in caller's execution context by default
- Use `@concurrent` to explicitly run code in parallel
- Data race safety is compiler-enforced in Swift 6

## Actors

Actors provide data isolation - only one task can access actor state at a time.

```swift
actor DataStore {
    private var cache: [String: Data] = [:]

    func get(_ key: String) -> Data? {
        cache[key]
    }

    func set(_ key: String, data: Data) {
        cache[key] = data
    }
}

// Usage - always async from outside
let store = DataStore()
let data = await store.get("key")
```

### nonisolated Methods

For computed properties or methods that don't access mutable state:

```swift
actor APIService {
    nonisolated var baseURL: URL {
        URL(string: "https://api.example.com")!
    }

    nonisolated func makeRequest(path: String) -> URLRequest {
        URLRequest(url: baseURL.appendingPathComponent(path))
    }
}
```

## @MainActor

Ensures code runs on the main thread. Use for UI-related code.

```swift
// Entire class on MainActor
@Observable @MainActor
final class ViewModel {
    var items: [Item] = []
    var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await fetchItems()
    }
}

// Single function
@MainActor
func updateUI() {
    // Safe to update UI here
}

// From nonisolated context
func processData() async {
    let result = await compute()
    await MainActor.run {
        self.data = result
    }
}
```

### Calling MainActor from Nonisolated

```swift
// Option 1: Task with MainActor
Task { @MainActor in
    viewModel.update(data)
}

// Option 2: MainActor.run
await MainActor.run {
    viewModel.update(data)
}
```

## Sendable

Types that can safely cross concurrency boundaries.

```swift
// Value types are implicitly Sendable
struct Config: Sendable {
    let apiKey: String
    let timeout: TimeInterval
}

// Classes need explicit conformance + immutability
final class ImmutableConfig: Sendable {
    let apiKey: String
    init(apiKey: String) { self.apiKey = apiKey }
}

// Actors are implicitly Sendable
actor Counter: Sendable { // Sendable is automatic
    var count = 0
}

// @unchecked for types you know are safe
final class ThreadSafeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    // ... implement thread-safe access
}
```

### Sendable Closures

```swift
// @Sendable closure - can cross isolation boundaries
func perform(_ action: @Sendable () async -> Void) async {
    await action()
}

// Task closures are implicitly @Sendable
Task {
    // This closure is @Sendable
    await viewModel.load()
}
```

## Task

### Structured Concurrency

```swift
// Task inherits actor context
@MainActor
func loadData() {
    Task {
        // Still on MainActor
        let data = await fetchData()
        self.data = data // Safe - same actor
    }
}

// Task.detached does NOT inherit context
Task.detached {
    // Not on MainActor - must explicitly switch
    let data = await fetchData()
    await MainActor.run {
        self.data = data
    }
}
```

### Task Groups

```swift
func loadAllImages(urls: [URL]) async -> [UIImage] {
    await withTaskGroup(of: UIImage?.self) { group in
        for url in urls {
            group.addTask {
                try? await loadImage(from: url)
            }
        }

        var images: [UIImage] = []
        for await image in group {
            if let image { images.append(image) }
        }
        return images
    }
}

// Throwing variant
func loadRequired(urls: [URL]) async throws -> [UIImage] {
    try await withThrowingTaskGroup(of: UIImage.self) { group in
        // ...
    }
}
```

### Task Cancellation

```swift
func longRunningWork() async throws {
    for i in 0..<1000 {
        // Check for cancellation
        try Task.checkCancellation()

        // Or handle gracefully
        if Task.isCancelled {
            cleanup()
            return
        }

        await processItem(i)
    }
}

// Cancel a task
let task = Task { await longRunningWork() }
task.cancel()
```

## AsyncSequence

```swift
// Iterate async
for await value in asyncStream {
    process(value)
}

// AsyncStream for bridging callbacks
let stream = AsyncStream<Int> { continuation in
    someCallbackAPI { value in
        continuation.yield(value)
    } onComplete: {
        continuation.finish()
    }
}
```

## Actor Reentrancy Warning

**Critical:** Between `await` calls, other tasks can access the actor and modify state.

```swift
actor BankAccount {
    var balance: Int = 100

    func withdraw(_ amount: Int) async -> Bool {
        // Check balance
        guard balance >= amount else { return false }

        // ⚠️ DANGER: Another task could run here during await
        await logTransaction(amount)

        // Balance might have changed!
        balance -= amount  // Could go negative
        return true
    }

    // SAFE: Make state changes synchronously before suspension
    func safeWithdraw(_ amount: Int) async -> Bool {
        guard balance >= amount else { return false }
        balance -= amount  // Change state BEFORE await
        await logTransaction(amount)
        return true
    }
}
```

**Rule:** Make state changes synchronously before suspension points.

## Common Patterns

### Actor-Isolated Protocol Conformance

```swift
protocol DataFetching: Sendable {
    func fetch() async throws -> Data
}

actor APIClient: DataFetching {
    func fetch() async throws -> Data {
        // Actor-isolated implementation
    }
}
```

### Combine Actor + MainActor ViewModel

```swift
actor DataService {
    func loadItems() async throws -> [Item] { ... }
}

@Observable @MainActor
final class ItemViewModel {
    var items: [Item] = []
    var error: Error?

    private let service = DataService()

    func refresh() async {
        do {
            items = try await service.loadItems()
        } catch {
            self.error = error
        }
    }
}
```

### Debouncing with Task

```swift
@Observable @MainActor
final class SearchViewModel {
    var query = "" {
        didSet { debounceSearch() }
    }
    var results: [Result] = []

    private var searchTask: Task<Void, Never>?

    private func debounceSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }
}
```

# SwiftData Reference

## @Model

Defines a persistent model. Macro generates Codable, Hashable, and more.

```swift
@Model
final class Item {
    var name: String
    var createdAt: Date
    var isComplete: Bool

    init(name: String) {
        self.name = name
        self.createdAt = .now
        self.isComplete = false
    }
}
```

### Unique Constraints

```swift
@Model
final class User {
    @Attribute(.unique) var email: String
    var name: String

    init(email: String, name: String) {
        self.email = email
        self.name = name
    }
}
```

### Relationships

```swift
@Model
final class Author {
    var name: String
    @Relationship(deleteRule: .cascade) var books: [Book] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class Book {
    var title: String
    var author: Author?

    init(title: String, author: Author? = nil) {
        self.title = title
        self.author = author
    }
}
```

### Composite Unique Key

```swift
@Model
final class TokenEntry {
    var projectId: String
    var timestamp: Date
    var tokens: Int

    // Composite unique identifier
    @Attribute(.unique) var compositeId: String

    init(projectId: String, timestamp: Date, tokens: Int) {
        self.projectId = projectId
        self.timestamp = timestamp
        self.tokens = tokens
        self.compositeId = "\(projectId)-\(timestamp.timeIntervalSince1970)"
    }
}
```

## ModelContainer

Configure in App struct:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Item.self, User.self])
    }
}
```

### Custom Configuration

```swift
@main
struct MyApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Item.self, User.self])
        let config = ModelConfiguration(
            "MyStore",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        container = try! ModelContainer(for: schema, configurations: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
```

## @Query

Fetch data reactively in views:

```swift
struct ItemListView: View {
    @Query private var items: [Item]

    var body: some View {
        List(items) { item in
            Text(item.name)
        }
    }
}
```

### Filtered and Sorted

```swift
struct ItemListView: View {
    @Query(
        filter: #Predicate<Item> { $0.isComplete == false },
        sort: \.createdAt,
        order: .reverse
    ) private var items: [Item]
}
```

### Dynamic Predicate

```swift
struct ItemListView: View {
    @State private var showCompleted = false

    var body: some View {
        ItemList(showCompleted: showCompleted)
    }
}

struct ItemList: View {
    @Query private var items: [Item]

    init(showCompleted: Bool) {
        _items = Query(
            filter: #Predicate<Item> { item in
                showCompleted || !item.isComplete
            },
            sort: \.createdAt
        )
    }
}
```

## ModelContext

### Insert and Delete

```swift
struct ItemListView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [Item]

    func addItem(name: String) {
        let item = Item(name: name)
        context.insert(item)
        // Auto-saves
    }

    func deleteItem(_ item: Item) {
        context.delete(item)
    }
}
```

### Batch Delete with Predicate

```swift
func deleteCompleted() throws {
    try context.delete(model: Item.self, where: #Predicate { $0.isComplete })
}
```

### Manual Save

```swift
func saveChanges() throws {
    if context.hasChanges {
        try context.save()
    }
}
```

## @ModelActor

For background operations without blocking UI:

```swift
@ModelActor
actor DataManager {
    func importItems(_ data: [ItemData]) throws {
        for item in data {
            let model = Item(name: item.name)
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func fetchSummary() throws -> Summary {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.isComplete }
        )
        let completed = try modelContext.fetchCount(descriptor)
        return Summary(completedCount: completed)
    }
}
```

### Using ModelActor

```swift
@Observable @MainActor
final class ViewModel {
    var summary: Summary?
    private let manager: DataManager

    init(container: ModelContainer) {
        self.manager = DataManager(modelContainer: container)
    }

    func loadSummary() async {
        summary = try? await manager.fetchSummary()
    }
}
```

## Predicate Examples

```swift
// Simple comparison
#Predicate<Item> { $0.name == "Test" }

// Contains
#Predicate<Item> { $0.name.contains("test") }

// Date range
let startDate = Calendar.current.startOfDay(for: .now)
#Predicate<Item> { $0.createdAt >= startDate }

// Multiple conditions
#Predicate<Item> { item in
    item.isComplete == false && item.name.contains("urgent")
}

// Optional handling
#Predicate<Item> { $0.category != nil }
```

## FetchDescriptor

For programmatic queries:

```swift
func fetchRecentItems() throws -> [Item] {
    var descriptor = FetchDescriptor<Item>(
        predicate: #Predicate { $0.createdAt > Date.now.addingTimeInterval(-86400) },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 10
    return try modelContext.fetch(descriptor)
}

func countIncomplete() throws -> Int {
    let descriptor = FetchDescriptor<Item>(
        predicate: #Predicate { !$0.isComplete }
    )
    return try modelContext.fetchCount(descriptor)
}
```

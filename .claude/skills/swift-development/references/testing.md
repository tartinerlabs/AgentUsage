# Swift Testing Reference

Swift Testing (iOS 18+, macOS 15+) - Modern replacement for XCTest.

## Basic Tests

```swift
import Testing

@Test func addition() {
    let result = 2 + 2
    #expect(result == 4)
}

@Test("User can be created with valid email")
func userCreation() {
    let user = User(email: "test@example.com")
    #expect(user.email == "test@example.com")
}
```

## Assertions

### #expect - Continues on failure

```swift
@Test func multipleExpectations() {
    let user = User(name: "John", age: 30)
    #expect(user.name == "John")      // If fails, continues
    #expect(user.age == 30)           // Still runs
    #expect(user.isAdult == true)     // Still runs
}
```

### #require - Stops on failure

```swift
@Test func requirePrecondition() throws {
    let data = loadData()
    let user = try #require(data.user) // Stops if nil
    #expect(user.name == "John")       // Only runs if above passes
}
```

### Throwing Tests

```swift
@Test func throwsError() throws {
    #expect(throws: ValidationError.self) {
        try validate(email: "invalid")
    }
}

@Test func throwsSpecificError() throws {
    #expect(throws: ValidationError.invalidEmail) {
        try validate(email: "invalid")
    }
}

@Test func doesNotThrow() throws {
    #expect(throws: Never.self) {
        try validate(email: "valid@test.com")
    }
}
```

## Test Organization

### @Suite

```swift
@Suite("User Authentication")
struct AuthenticationTests {
    @Test func validLogin() { }
    @Test func invalidPassword() { }
    @Test func expiredSession() { }
}

@Suite("User Authentication", .serialized)
struct SerialAuthTests {
    // Tests run one at a time
}
```

### Nested Suites

```swift
@Suite struct APITests {
    @Suite struct UserEndpoints {
        @Test func fetchUser() { }
        @Test func updateUser() { }
    }

    @Suite struct ItemEndpoints {
        @Test func listItems() { }
    }
}
```

## Async Testing

```swift
@Test func asyncFetch() async throws {
    let service = APIService()
    let data = try await service.fetchData()
    #expect(data.isEmpty == false)
}

@Test func asyncWithTimeout() async throws {
    try await withTimeout(seconds: 5) {
        let result = await longRunningOperation()
        #expect(result.isValid)
    }
}
```

### Testing Actors

```swift
actor Counter {
    var value = 0
    func increment() { value += 1 }
}

@Test func counterIncrement() async {
    let counter = Counter()
    await counter.increment()
    let value = await counter.value
    #expect(value == 1)
}
```

### Testing MainActor

```swift
@Observable @MainActor
final class ViewModel {
    var items: [Item] = []
    func load() async { items = await fetchItems() }
}

@Test @MainActor func viewModelLoads() async {
    let viewModel = ViewModel()
    await viewModel.load()
    #expect(viewModel.items.isEmpty == false)
}
```

## Parameterized Tests

```swift
@Test(arguments: [1, 2, 3, 4, 5])
func isPositive(number: Int) {
    #expect(number > 0)
}

@Test(arguments: [
    ("hello", 5),
    ("world", 5),
    ("", 0)
])
func stringLength(input: String, expected: Int) {
    #expect(input.count == expected)
}

@Test(arguments: zip(["a", "b"], [1, 2]))
func pairedArguments(letter: String, number: Int) {
    #expect(!letter.isEmpty)
    #expect(number > 0)
}
```

## Test Traits

### Skip Tests

```swift
@Test(.disabled("Not implemented yet"))
func futureFeature() { }

@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
func ciOnly() { }
```

### Tags

```swift
extension Tag {
    @Tag static var slow: Self
    @Tag static var integration: Self
}

@Test(.tags(.slow, .integration))
func slowIntegrationTest() { }
```

### Time Limit

```swift
@Test(.timeLimit(.minutes(1)))
func mustCompleteQuickly() async {
    await someOperation()
}
```

## Mocking

### Protocol-Based Mocking

```swift
protocol DataFetching {
    func fetch() async throws -> [Item]
}

struct MockFetcher: DataFetching {
    var items: [Item] = []
    var shouldThrow = false

    func fetch() async throws -> [Item] {
        if shouldThrow { throw FetchError.failed }
        return items
    }
}

@Test func viewModelWithMock() async {
    let mock = MockFetcher(items: [Item(name: "Test")])
    let viewModel = ViewModel(fetcher: mock)
    await viewModel.load()
    #expect(viewModel.items.count == 1)
}
```

### Actor Mocking

```swift
protocol APIClient: Sendable {
    func fetch() async throws -> Data
}

actor MockAPIClient: APIClient {
    var mockData: Data = Data()
    var fetchCount = 0

    func fetch() async throws -> Data {
        fetchCount += 1
        return mockData
    }
}

@Test func serviceUsesMock() async throws {
    let mock = MockAPIClient()
    await mock.setMockData(testData)

    let service = Service(client: mock)
    let result = try await service.process()

    #expect(result != nil)
    #expect(await mock.fetchCount == 1)
}
```

## Setup and Teardown

```swift
@Suite struct DatabaseTests {
    let database: TestDatabase

    init() async throws {
        database = try await TestDatabase.create()
    }

    deinit {
        // Cleanup
    }

    @Test func insert() async throws {
        try await database.insert(Item(name: "Test"))
        let items = try await database.fetchAll()
        #expect(items.count == 1)
    }
}
```

## Testing SwiftData

```swift
@Test func swiftDataInsert() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Item.self, configurations: config)
    let context = container.mainContext

    let item = Item(name: "Test")
    context.insert(item)
    try context.save()

    let descriptor = FetchDescriptor<Item>()
    let items = try context.fetch(descriptor)
    #expect(items.count == 1)
    #expect(items.first?.name == "Test")
}
```

## Comparison: XCTest vs Swift Testing

| XCTest | Swift Testing |
|--------|---------------|
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(x)` | `#expect(x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertThrowsError` | `#expect(throws:)` |
| `func testFoo()` | `@Test func foo()` |
| `class FooTests: XCTestCase` | `@Suite struct FooTests` |
| `override func setUp()` | `init()` |

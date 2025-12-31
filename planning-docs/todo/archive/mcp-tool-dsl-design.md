# MCP Tool DSL Design Document

A declarative Swift DSL for defining MCP tools, inspired by Apple's App Intents framework.

**Target:** PR for the [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
**Swift Version:** 5.9+ (uses macros)
**Dependency:** Requires JSON Schema validator infrastructure using [swift-json-schema](https://github.com/ajevans99/swift-json-schema) (see `schema-validation/swift-sdk-comparison.md`)

## Goals

1. **Reduce boilerplate** - Eliminate manual JSON Schema construction
2. **Type safety** - Catch errors at compile time, not runtime
3. **Familiar patterns** - Follow App Intents conventions Swift developers already know
4. **Single source of truth** - Schema and execution defined together, not duplicated
5. **Unified validation** - Leverage the SDK's JSON Schema validator for all constraint enforcement

## Current Pain Points

```swift
// Current approach: 50+ lines per tool
ToolRegistration(
  definition: Tool(
    name: "create_calendar_event",
    description: "Create a new calendar event",
    inputSchema: .object([
      "type": .string("object"),
      "properties": .object([
        "title": .object([
          "type": .string("string"),
          "description": .string("The title of the event"),
        ]),
        // ... repeat for every parameter
      ]),
      "required": .array([.string("title"), .string("start_date")]),
    ]),
    annotations: Tool.Annotations(...)
  ),
  execute: { args in
    guard let title = args?["title"]?.stringValue else {
      throw ToolError.invalidArgument("'title' argument is required")
    }
    // ... repeat validation for every required parameter
    return try await CalendarEvents.createEvent(...)
  }
)
```

**Problems:**
- Schema defined separately from execution logic
- Required fields validated twice (schema + execute closure)
- String keys repeated and error-prone
- Verbose nested dictionary syntax
- No compile-time type checking

## Proposed Design

### Core Protocol: `ToolSpec`

Following App Intents' `AppIntent` protocol pattern. The `@Tool` macro adds
conformance to the `ToolSpec` protocol (similar to SwiftData's `@Model` → `PersistentModel`):

```swift
/// A tool that can be invoked via MCP.
/// Uses an attached macro to generate schema and parsing code.
@attached(member, names: named(toolDefinition), named(parse), named(init))
@attached(extension, conformances: ToolSpec)
public macro Tool() = #externalMacro(module: "MCPMacros", type: "ToolMacro")

/// The protocol for MCP tools (conformance added by @Tool macro).
public protocol ToolSpec: Sendable {
  /// The result type returned by perform().
  associatedtype Output: ToolOutput

  /// The Tool definition including name, description, and JSON Schema.
  static var toolDefinition: Tool { get }

  /// Annotations describing tool behavior (read-only, idempotent, etc.).
  /// Default is empty array (MCP implicit defaults apply).
  static var annotations: [AnnotationOption] { get }

  /// Parse validated arguments into a typed instance.
  /// Called AFTER JSON Schema validation has passed.
  /// Can assume arguments conform to the schema.
  static func parse(from arguments: [String: Value]?) throws -> Self

  /// Performs the tool's action with typed parameters.
  /// Context provides progress reporting and logging (TypeScript-style: always passed).
  func perform(context: ToolContext) async throws -> Output

  /// Required for initialization during execution.
  /// Note: The macro generates this automatically; users don't need to write it.
  init()
}

extension ToolSpec {
  /// Default: empty array (MCP implicit defaults apply).
  public static var annotations: [AnnotationOption] { [] }
}

/// Context for DSL tools - wraps RequestHandlerContext with tool-friendly API.
/// Always passed to perform() (TypeScript-style). Tools can ignore if not needed.
public struct ToolContext: Sendable {
  private let handlerContext: RequestHandlerContext
  private let progressToken: ProgressToken?

  init(handlerContext: RequestHandlerContext, progressToken: ProgressToken?) {
    self.handlerContext = handlerContext
    self.progressToken = progressToken
  }

  // MARK: - Cancellation (wraps Swift's cooperative cancellation)

  /// Check if the current request has been cancelled.
  /// Equivalent to `Task.isCancelled`.
  public var isCancelled: Bool {
    Task.isCancelled
  }

  /// Throws `CancellationError` if the request has been cancelled.
  /// Use this at cancellation points in long-running operations.
  public func checkCancellation() throws {
    try Task.checkCancellation()
  }

  // MARK: - Progress

  /// Report progress for the current operation.
  /// Silently ignored if the request didn't include a progress token.
  public func reportProgress(
    _ progress: Double,
    total: Double? = nil,
    message: String? = nil
  ) async throws {
    guard let token = progressToken else { return }
    try await handlerContext.sendProgress(token: token, progress: progress, total: total, message: message)
  }

  // MARK: - Logging

  /// Log at info level.
  public func info(_ message: String) async throws {
    try await handlerContext.sendLogMessage(level: .info, data: .string(message))
  }

  /// Log at debug level.
  public func debug(_ message: String) async throws {
    try await handlerContext.sendLogMessage(level: .debug, data: .string(message))
  }

  /// Log at warning level.
  public func warning(_ message: String) async throws {
    try await handlerContext.sendLogMessage(level: .warning, data: .string(message))
  }

  /// Log at error level.
  public func error(_ message: String) async throws {
    try await handlerContext.sendLogMessage(level: .error, data: .string(message))
  }
}
```

**Key design decision:** The protocol does NOT include an `execute(arguments:)` method.
Validation and execution are handled by `ToolRegistry`, which:
1. Validates arguments against `toolDefinition.inputSchema` using `JSONSchemaValidator`
2. Calls `parse(from:)` to convert validated arguments to a typed instance
3. Calls `perform()` to execute the tool
4. Validates output against `outputSchema` if present

This separation ensures:
- All constraint enforcement happens in the validator (single source of truth)
- `parse(from:)` uses defensive guards with clear error messages (safe even if validation is skipped)
- DSL tools and manual tools use the same validation infrastructure
- Parse failures throw recoverable errors (server stays up), aligning with Python/TypeScript behavior

**App Intents-style usage:**

```swift
@Tool
struct CreateCalendarEvent {
  // Metadata (like AppIntent's static var title/description)
  static let name = "create_calendar_event"
  static let description = "Create a new calendar event"

  // Parameters (like AppIntent's @Parameter)
  @Parameter(description: "The title of the event")
  var title: String

  @Parameter(key: "start_date", description: "Start date/time in ISO 8601 format")
  var startDate: Date

  // Execution (like AppIntent's perform())
  // Context always passed (TypeScript-style) - use for progress/logging, or ignore
  func perform(context: ToolContext) async throws -> String {
    try await CalendarEvents.createEvent(
      title: title,
      startDate: startDate
    )
  }
}
```

The `@Tool` macro generates `toolDefinition` and `parse(from:)` by inspecting
the `@Parameter` properties. This mirrors how App Intents works internally.

### Parameters: `@Parameter` Property Wrapper

Mirrors App Intents' `@Parameter`:

```swift
@propertyWrapper
public struct Parameter<Value: ParameterValue>: Sendable {
  public var wrappedValue: Value

  /// The JSON key used in the schema and argument parsing.
  /// If nil, the Swift property name is used exactly as written.
  let key: String?
  let description: String?

  // Validation constraints (included in JSON Schema)
  let minLength: Int?       // For strings
  let maxLength: Int?       // For strings
  let minimum: Double?      // For numbers
  let maximum: Double?      // For numbers

  // For required parameters (non-optional Value)
  public init(
    wrappedValue: Value,
    key: String? = nil,
    description: String? = nil,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil
  ) { ... }

  // For optional parameters (no wrappedValue needed)
  public init(
    key: String? = nil,
    description: String? = nil,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil
  ) where Value: ExpressibleByNilLiteral { ... }
}
```

**Key naming:**

The JSON key defaults to the Swift property name exactly as written. Use `key:` to override:

```swift
// Property name used as-is → JSON key is "title"
@Parameter(description: "Event title", maxLength: 500)
var title: String

// Explicit key override → JSON key is "start_date"
@Parameter(key: "start_date", description: "Start date/time in ISO 8601 format")
var startDate: Date

// Explicit key override → JSON key is "num_results"
@Parameter(key: "num_results", description: "Number of results", minimum: 1, maximum: 100)
var limit: Int = 50
```

This follows the same pattern as MLX Swift and similar to `CodingKeys` in Codable—explicit
is better than magic conversion.

**Default values:**

Use standard Swift syntax for default values. The macro extracts the literal from source
and includes it in the JSON Schema's `default` field:

```swift
@Parameter(description: "Maximum events to return", minimum: 1, maximum: 500)
var limit: Int = 50

// Generates schema:
// "limit": {
//   "type": "integer",
//   "description": "Maximum events to return",
//   "minimum": 1,
//   "maximum": 500,
//   "default": 50
// }
```

Parameters with defaults are **not** included in the `required` array, since the tool
can use the default if the argument is omitted.

**Limitation:** Only literal default values are supported. Swift macros can parse syntax
but cannot evaluate expressions at compile time:

```swift
// ✅ Supported (literals)
var limit: Int = 50
var name: String = "default"
var enabled: Bool = true

// ❌ Not supported (expressions) - will emit compile-time error
var date: Date = Date()
var config: Config = .default
var id: String = UUID().uuidString
```

For complex defaults, make the parameter optional and handle the default in `perform()`:

```swift
@Parameter(description: "Start date. Defaults to now.")
var startDate: Date?

func perform() async throws -> some ToolResult {
  let start = startDate ?? Date()
  // ...
}
```

### Supported Parameter Types: `ParameterValue`

```swift
/// Types that can be used as MCP tool parameters.
public protocol ParameterValue: Sendable {
  /// The JSON Schema type name.
  static var jsonSchemaType: String { get }

  /// Additional schema properties (e.g., enum values, contentEncoding).
  static var jsonSchemaProperties: [String: Value] { get }

  /// Parse from MCP Value. Returns nil if the value cannot be converted.
  /// Matches the SDK's existing pattern: `String.init?(_ value: Value)`, etc.
  /// The macro generates appropriate error messages using the parameter name.
  init?(_ value: Value)
}

// Built-in conformances: String, Int, Double, Bool already have init?(_ value: Value)
// in the SDK, so they only need the static schema properties.
extension String: ParameterValue {
  public static var jsonSchemaType: String { "string" }
  public static var jsonSchemaProperties: [String: Value] { [:] }
  // init?(_ value: Value) already exists in MCP SDK (Value.swift:388)
}

extension Int: ParameterValue {
  public static var jsonSchemaType: String { "integer" }
  public static var jsonSchemaProperties: [String: Value] { [:] }
  // init?(_ value: Value) already exists in MCP SDK (Value.swift:320)
}

extension Double: ParameterValue {
  public static var jsonSchemaType: String { "number" }
  public static var jsonSchemaProperties: [String: Value] { [:] }
  // init?(_ value: Value) already exists in MCP SDK (Value.swift:354)
}

extension Bool: ParameterValue {
  public static var jsonSchemaType: String { "boolean" }
  public static var jsonSchemaProperties: [String: Value] { [:] }
  // init?(_ value: Value) already exists in MCP SDK (Value.swift:270)
}

extension Date: ParameterValue {
  public static var jsonSchemaType: String { "string" }
  public static var jsonSchemaProperties: [String: Value] {
    ["format": .string("date-time")]
  }
  public init?(_ value: Value) {
    guard let str = String(value),
          let date = ISO8601DateFormatter().date(from: str) else {
      return nil
    }
    self = date
  }
}

extension Data: ParameterValue {
  public static var jsonSchemaType: String { "string" }
  public static var jsonSchemaProperties: [String: Value] {
    ["contentEncoding": .string("base64")]
  }
  public init?(_ value: Value) {
    guard let (_, data) = value.dataValue else { return nil }
    self = data
  }
}

extension Optional: ParameterValue where Wrapped: ParameterValue {
  public static var jsonSchemaType: String { Wrapped.jsonSchemaType }
  public static var jsonSchemaProperties: [String: Value] { Wrapped.jsonSchemaProperties }
  public init?(_ value: Value) {
    if value.isNull {
      self = .none
    } else if let wrapped = Wrapped(value) {
      self = .some(wrapped)
    } else {
      return nil
    }
  }
}

extension Array: ParameterValue where Element: ParameterValue {
  public static var jsonSchemaType: String { "array" }
  public static var jsonSchemaProperties: [String: Value] {
    var itemSchema: [String: Value] = ["type": .string(Element.jsonSchemaType)]
    for (key, value) in Element.jsonSchemaProperties {
      itemSchema[key] = value
    }
    return ["items": .object(itemSchema)]
  }
  public init?(_ value: Value) {
    guard let array = value.arrayValue else { return nil }
    var result: [Element] = []
    for item in array {
      guard let element = Element(item) else { return nil }
      result.append(element)
    }
    self = result
  }
}

// Example: @Parameter var tags: [String] generates:
// "tags": {
//   "type": "array",
//   "items": { "type": "string" }
// }
```

The macro generates error messages with parameter context:

```swift
// For required parameter 'title':
guard let titleValue = arguments?["title"],
      let title = String(titleValue) else {
  throw MCPError.invalidParams("'title' argument is required and must be a string")
}
```

### Enum Parameters: `ToolEnum`

Following App Intents' pattern for type-safe enums:

```swift
/// An enum that can be used as an MCP parameter.
public protocol ToolEnum: ParameterValue, CaseIterable, RawRepresentable
  where RawValue == String {}

extension ToolEnum {
  public static var jsonSchemaType: String { "string" }
  public static var jsonSchemaProperties: [String: Value] {
    ["enum": .array(allCases.map { .string($0.rawValue) })]
  }
}

// Usage
enum EventSpan: String, ToolEnum {
  case thisEvent = "this"
  case futureEvents = "future"
}
```

### Annotations: `AnnotationOption`

Annotations are specified as an array of `AnnotationOption` values. The `ToolSpec` protocol
declares the type, so Swift infers it automatically—no type annotation needed.

```swift
/// Options for annotating MCP tool behavior.
/// Specified as an array; the macro validates for conflicts at compile time.
public enum AnnotationOption: Sendable {
  /// Tool only reads data, has no side effects.
  /// Automatically implies non-destructive and idempotent.
  case readOnly

  /// Tool can be safely called multiple times with the same result.
  case idempotent

  /// Tool does not interact with external systems (closed world).
  case closedWorld

  /// Human-readable title for UI display.
  case title(String)

  // Note: No `.destructive` case—it's the MCP implicit default.
  // If you don't specify `.readOnly`, the tool is assumed to be potentially destructive.
}
```

**MCP implicit defaults** (when annotations array is empty):
- `readOnlyHint: false` — tool may modify state
- `destructiveHint: true` — tool may destroy data
- `idempotentHint: false` — repeated calls may have different effects
- `openWorldHint: true` — tool interacts with external systems

The protocol provides a default empty array, so `annotations` can be omitted entirely:

```swift
public protocol ToolSpec: Sendable {
  static var annotations: [AnnotationOption] { get }
  // ... other requirements
}

extension ToolSpec {
  public static var annotations: [AnnotationOption] { [] }
}
```

**Usage:**

```swift
// Read-only tool (automatically sets destructive: false, idempotent: true)
static let annotations = [.readOnly]

// Read-only with display title
static let annotations = [.readOnly, .title("List Calendar Events")]

// Idempotent (like delete—can call multiple times safely)
static let annotations = [.idempotent]

// Multiple options
static let annotations = [.idempotent, .closedWorld]

// Default behavior (potentially destructive, not idempotent)
// Just omit the property entirely, or:
static let annotations: [AnnotationOption] = []
```

**Compile-time validation:**

The `@Tool` macro validates annotations at compile time:

```swift
// Duplicate annotations
static let annotations = [.readOnly, .title("A"), .title("B")]
// ❌ error: Duplicate '.title' annotations

static let annotations = [.idempotent, .idempotent]
// ❌ error: Duplicate '.idempotent' annotations

// Redundant annotations
static let annotations = [.readOnly, .idempotent]
// ⚠️ warning: '.idempotent' is redundant when '.readOnly' is specified
```

Validation rules:
- **Error**: Duplicate `.title(...)` — which value wins is ambiguous
- **Error**: Duplicate `.readOnly`, `.idempotent`, or `.closedWorld`
- **Warning**: `.idempotent` with `.readOnly` — redundant since `.readOnly` implies idempotent

The macro converts `[AnnotationOption]` to `Tool.Annotations` when generating `toolDefinition`.

### Results: `ToolOutput`

MCP SDK's `Tool.Content` supports multiple content types:
```swift
// From MCP SDK
public enum Tool.Content: Hashable, Codable, Sendable {
  case text(String)
  case image(data: String, mimeType: String, metadata: [String: String]?)
  case audio(data: String, mimeType: String)
  case resource(uri: String, mimeType: String, text: String?)
}
```

Our DSL provides a protocol for type-safe result handling:
```swift
/// A type that can be returned from an MCP tool's perform() method.
public protocol ToolOutput: Sendable {
  /// Convert to CallTool.Result for the response.
  /// Throws on encoding failure - server returns error, doesn't crash.
  func toCallToolResult() throws -> CallTool.Result
}
```

**Built-in conformances:**

```swift
// Most tools return text/JSON - this is the common case
extension String: ToolOutput {
  public func toCallToolResult() throws -> CallTool.Result {
    CallTool.Result(content: [.text(self)])
  }
}
```

**Image results:**

```swift
public struct ImageOutput: ToolOutput {
  public let data: Data
  public let mimeType: String
  public let metadata: [String: String]?

  public init(data: Data, mimeType: String, metadata: [String: String]? = nil) {
    self.data = data
    self.mimeType = mimeType
    self.metadata = metadata
  }

  public init(pngData: Data, metadata: [String: String]? = nil) {
    self.init(data: pngData, mimeType: "image/png", metadata: metadata)
  }

  public init(jpegData: Data, metadata: [String: String]? = nil) {
    self.init(data: jpegData, mimeType: "image/jpeg", metadata: metadata)
  }

  public func toCallToolResult() throws -> CallTool.Result {
    CallTool.Result(content: [.image(data: data.base64EncodedString(), mimeType: mimeType, metadata: metadata)])
  }
}
```

**Audio results:**

```swift
public struct AudioOutput: ToolOutput {
  public let data: Data
  public let mimeType: String

  public init(data: Data, mimeType: String) {
    self.data = data
    self.mimeType = mimeType
  }

  public func toCallToolResult() throws -> CallTool.Result {
    CallTool.Result(content: [.audio(data: data.base64EncodedString(), mimeType: mimeType)])
  }
}
```

**Multiple content items:**

```swift
public struct MultiContent: ToolOutput {
  public let items: [Tool.Content]

  public init(_ items: [Tool.Content]) {
    self.items = items
  }

  public func toCallToolResult() throws -> CallTool.Result {
    CallTool.Result(content: items)
  }
}
```

### Structured Output with Schema Validation

For tools that need output schema validation (matching TypeScript/Python SDK behavior),
return a type conforming to `StructuredOutput`:

```swift
/// Protocol for structured outputs that can be validated against a schema.
public protocol StructuredOutput: ToolOutput, Encodable {
  /// JSON Schema for this output type (generated by @OutputSchema macro).
  static var schema: Value { get }
}

/// Macro to generate output schema from an Encodable struct.
@attached(extension, conformances: StructuredOutput)
@attached(member, names: named(schema))
public macro OutputSchema() = #externalMacro(module: "MCPMacros", type: "OutputSchemaMacro")
```

**Default implementation for StructuredOutput:**

```swift
extension StructuredOutput {
  public func toCallToolResult() throws -> CallTool.Result {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(self)
    guard let json = String(data: data, encoding: .utf8) else {
      throw MCPError.internalError("Failed to encode output as UTF-8 string")
    }
    let structured = try JSONDecoder().decode(Value.self, from: data)
    return CallTool.Result(
      content: [.text(json)],
      structuredContent: structured
    )
  }
}
```

**Single macro with automatic output schema detection:**

The `@Tool` macro automatically detects whether the return type has an output schema
by checking if `Output` conforms to `StructuredOutput` at runtime. This aligns with
TypeScript/Python's single-entry-point pattern:

```swift
// Generated by @Tool macro
static var toolDefinition: Tool {
  Tool(
    name: name,
    description: description,
    inputSchema: ...,
    outputSchema: (Output.self as? StructuredOutput.Type)?.schema  // nil if not StructuredOutput
  )
}
```

**Usage:**

```swift
// Define a structured output type with schema
@OutputSchema
struct EventList: StructuredOutput {
  let events: [CalendarEvent]
  let totalCount: Int
}

// Same @Tool macro - output schema is auto-detected from return type
@Tool
struct GetCalendarEvents {
  static let name = "get_calendar_events"
  static let description = "Get calendar events"
  static let annotations: [AnnotationOption] = [.readOnly]

  @Parameter(description: "Maximum events to return", minimum: 1, maximum: 100)
  var limit: Int = 25

  func perform(context: ToolContext) async throws -> EventList {  // EventList conforms to StructuredOutput
    let events = try await CalendarEvents.list(limit: limit)
    return EventList(events: events, totalCount: events.count)
  }
}

// Simple tool - no output schema (String doesn't conform to StructuredOutput)
@Tool
struct GetCalendars {
  static let name = "get_calendars"
  static let description = "Get all calendars"

  func perform(context: ToolContext) async throws -> String {
    try await CalendarEvents.getCalendars()  // context unused, that's fine
  }
}
```

**How it works:**

| Return Type | Conforms to StructuredOutput? | Output Schema |
|-------------|-------------------------------|---------------|
| `String` | No | None |
| `ImageOutput` | No | None |
| `EventList` | Yes (via `@OutputSchema`) | `EventList.schema` |

Server validates output against `outputSchema` (if present) after tool execution.
All failures return errors - the server never crashes.

**Usage with `perform(context:)`:**

Tools return concrete types that conform to `ToolOutput`. Context is always passed
(TypeScript-style) for progress reporting and logging:

```swift
// Most tools return String (text content)
func perform(context: ToolContext) async throws -> String {
  try await CalendarEvents.getEvents()
}

// Image-returning tool
func perform(context: ToolContext) async throws -> ImageOutput {
  let imageData = try await captureScreen()
  return ImageOutput(pngData: imageData)
}

// Structured output with schema validation
func perform(context: ToolContext) async throws -> EventList {
  let events = try await fetchEvents()
  return EventList(events: events, totalCount: events.count)
}

// Using context for progress, logging, and cancellation
func perform(context: ToolContext) async throws -> String {
  for i in 0..<items.count {
    // Check for cancellation at each iteration
    try context.checkCancellation()

    try await context.reportProgress(Double(i), total: Double(items.count))
    try await context.info("Processing item \(i)")
    // ... process item
  }
  return "Processed \(items.count) items"
}
```

## Complete Example

### Before (Current Approach)

```swift
let calendarTools: [ToolRegistration] = [
  ToolRegistration(
    definition: Tool(
      name: "create_calendar_event",
      description: "Create a new calendar event",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "title": .object([
            "type": .string("string"),
            "description": .string("The title of the event"),
          ]),
          "start_date": .object([
            "type": .string("string"),
            "description": .string("Start date/time in ISO 8601 format"),
          ]),
          "end_date": .object([
            "type": .string("string"),
            "description": .string("End date/time. Defaults to 1 hour after start."),
          ]),
          "location": .object([
            "type": .string("string"),
            "description": .string("Location of the event"),
          ]),
          "notes": .object([
            "type": .string("string"),
            "description": .string("Notes for the event"),
          ]),
        ]),
        "required": .array([.string("title"), .string("start_date")]),
      ]),
      annotations: Tool.Annotations(
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: false
      )
    ),
    execute: { args in
      guard let title = args?["title"]?.stringValue else {
        throw ToolError.invalidArgument("'title' argument is required")
      }
      guard let startDateStr = args?["start_date"]?.stringValue,
            let startDate = parseDate(startDateStr)
      else {
        throw ToolError.invalidArgument("'start_date' is required")
      }
      return try await CalendarEvents.createEvent(
        title: title,
        startDate: startDate,
        endDate: parseDate(args?["end_date"]?.stringValue),
        location: args?["location"]?.stringValue,
        notes: args?["notes"]?.stringValue
      )
    }
  ),
]
```

### After (Proposed DSL)

```swift
@Tool
struct CreateCalendarEvent {
  static let name = "create_calendar_event"
  static let description = "Create a new calendar event"

  @Parameter(description: "The title of the event")
  var title: String

  @Parameter(key: "start_date", description: "Start date/time in ISO 8601 format")
  var startDate: Date

  @Parameter(key: "end_date", description: "End date/time. Defaults to 1 hour after start.")
  var endDate: Date?

  @Parameter(description: "Location of the event")
  var location: String?

  @Parameter(description: "Notes for the event")
  var notes: String?

  func perform() async throws -> String {
    try await CalendarEvents.createEvent(
      title: title,
      startDate: startDate,
      endDate: endDate,
      location: location,
      notes: notes
    )
  }
}
```

**Comparison with App Intents:**
```swift
// App Intents                          // MCP Tool DSL
struct MyIntent: AppIntent {            @Tool
                                        struct MyTool {
  static var title: LocalizedString...    static let name = "my_tool"
  static var description = Intent...      static let description = "..."

  @Parameter(title: "Name")               @Parameter(description: "Name")
  var name: String                        var name: String

  func perform() async throws             func perform() async throws
    -> some IntentResult                    -> String  // or any ToolOutput
}                                       }
```

**Improvements:**
- 50+ lines → 25 lines
- Type-safe parameters (no string keys)
- Required vs optional expressed via Swift's type system
- Schema generated at compile time by macro
- No manual validation code
- Compile-time errors for invalid tool definitions
- Familiar pattern for developers who know App Intents

### More Examples

```swift
// Read-only tool with no parameters
@Tool
struct GetCalendars {
  static let name = "get_calendars"
  static let description = "Get all available calendars"
  static let annotations: [AnnotationOption] = [.readOnly]

  func perform(context: ToolContext) async throws -> String {
    try await CalendarEvents.getCalendars()
  }
}

// Tool with enum parameter
@Tool
struct DeleteCalendarEvent {
  static let name = "delete_calendar_event"
  static let description = "Delete a calendar event"
  static let annotations: [AnnotationOption] = [.idempotent]  // Destructive is implicit default

  @Parameter(description: "The event ID to delete")
  var id: String

  @Parameter(description: "For recurring events: 'this' or 'future'")
  var span: EventSpan?

  func perform(context: ToolContext) async throws -> String {
    try await CalendarEvents.deleteEvent(id: id, span: span)
  }
}

// Tool with default values and structured output (auto-detected via return type)
@OutputSchema
struct EventListOutput: StructuredOutput {
  let events: [CalendarEvent]
  let hasMore: Bool
}

@Tool  // Same macro - output schema auto-detected because EventListOutput conforms to StructuredOutput
struct GetCalendarEvents {
  static let name = "get_calendar_events"
  static let description = "Get calendar events within a date range"
  static let annotations: [AnnotationOption] = [.readOnly, .title("List Calendar Events")]

  @Parameter(key: "start_date", description: "Start date. Defaults to now.")
  var startDate: Date?

  @Parameter(key: "end_date", description: "End date. Defaults to 7 days from start.")
  var endDate: Date?

  @Parameter(description: "Maximum events to return (1-500)", minimum: 1, maximum: 500)
  var limit: Int = 50

  func perform(context: ToolContext) async throws -> EventListOutput {
    try await context.info("Fetching events...")
    let events = try await CalendarEvents.getEvents(
      startDate: startDate,
      endDate: endDate,
      limit: limit + 1  // Fetch one extra to check hasMore
    )
    return EventListOutput(
      events: Array(events.prefix(limit)),
      hasMore: events.count > limit
    )
  }
}
```

## Tool Registration

### ToolRegistry

The `ToolRegistry` is responsible for:
1. Storing registered `ToolSpec` types
2. Providing tool definitions for `ListTools`
3. Parsing and executing tools (validation is handled by Server)

```swift
public actor ToolRegistry {
  private var tools: [String: any ToolSpec.Type] = [:]

  public init() {}

  public func register<T: ToolSpec>(_ tool: T.Type) {
    tools[T.toolDefinition.name] = tool
  }

  /// All tool definitions for ListTools response.
  public var definitions: [Tool] {
    tools.values.map { $0.toolDefinition }
  }

  /// Check if registry handles a tool.
  public func hasTool(_ name: String) -> Bool {
    tools[name] != nil
  }

  /// Execute a tool (validation already done by Server).
  public func execute(
    _ name: String,
    arguments: [String: Value]?,
    context: ToolContext
  ) async throws -> CallTool.Result {
    guard let toolType = tools[name] else {
      throw MCPError.methodNotFound("Unknown tool: \(name)")
    }

    // Parse into typed instance (Server already validated)
    let instance = try toolType.parse(from: arguments)

    // Execute and convert output (both can throw - returns error, doesn't crash)
    let output = try await instance.perform(context: context)
    return try output.toCallToolResult()
  }
}
```

**Note:** ToolRegistry does not validate - that's Server's responsibility. This matches
how Python and TypeScript SDKs work, where the server handles all validation.
Server validates input before calling `execute()`, and validates output after.

### Explicit Registration

```swift
let registry = ToolRegistry()
await registry.register(GetCalendars.self)
await registry.register(GetCalendarEvents.self)
await registry.register(CreateCalendarEvent.self)
await registry.register(DeleteCalendarEvent.self)
```

### Result Builder (Optional)

For convenience, a result builder can collect tools:

```swift
let registry = ToolRegistry {
  GetCalendars.self
  GetCalendarEvents.self
  CreateCalendarEvent.self
  DeleteCalendarEvent.self
}
```

Implementation:
```swift
@resultBuilder
public struct ToolBuilder {
  public static func buildBlock(_ tools: (any ToolSpec.Type)...) -> [any ToolSpec.Type] {
    tools
  }
}

extension ToolRegistry {
  /// Synchronous init with result builder (actor init runs in isolation).
  public init(@ToolBuilder tools: () -> [any ToolSpec.Type]) {
    let toolList = tools()
    self.tools = Dictionary(uniqueKeysWithValues: toolList.map {
      ($0.toolDefinition.name, $0)
    })
  }
}
```

### Schema Generation (Compile-Time)

The `@Tool` macro generates schemas at compile time by analyzing `@Parameter` properties:

```swift
// The macro analyzes this at compile time:
@Parameter(description: "The title")
var title: String

@Parameter(key: "start_date", description: "Start date/time")
var startDate: Date

@Parameter(description: "Optional notes")
var notes: String?

@Parameter(description: "Max results", minimum: 1, maximum: 100)
var limit: Int = 25

// And generates this schema:
.object([
  "type": .string("object"),
  "properties": .object([
    "title": .object([
      "type": .string("string"),
      "description": .string("The title")
    ]),
    "start_date": .object([
      "type": .string("string"),
      "description": .string("Start date/time")
    ]),
    "notes": .object([
      "type": .string("string"),
      "description": .string("Optional notes")
    ]),
    "limit": .object([
      "type": .string("integer"),
      "description": .string("Max results"),
      "minimum": .int(1),
      "maximum": .int(100),
      "default": .int(25)
    ])
  ]),
  // title and start_date are required; notes is optional; limit has a default
  "required": .array([.string("title"), .string("start_date")])
])
```

Benefits of compile-time generation:
- **Zero runtime overhead** - No reflection needed
- **Type safety** - Invalid schemas caught at compile time
- **Better diagnostics** - Macro can emit helpful error messages

### Server Integration

The Server is the single source of validation for all tools (matching Python/TypeScript SDKs):

```swift
public actor Server {
  private let validator: JSONSchemaValidator
  private var toolCache: [String: Tool] = [:]
  private var toolRegistry: ToolRegistry?

  public init(
    info: Implementation,
    capabilities: ServerCapabilities,
    validator: JSONSchemaValidator = DefaultJSONSchemaValidator()
  ) {
    self.validator = validator
    // ...
  }

  // MARK: - Tool Registration

  /// Register DSL tools via registry.
  public func registerTools(_ registry: ToolRegistry) async {
    self.toolRegistry = registry
    for tool in await registry.definitions {
      toolCache[tool.name] = tool
    }
  }

  /// Register manual tools (for non-DSL usage).
  public func registerTools(_ tools: [Tool]) {
    for tool in tools {
      toolCache[tool.name] = tool
    }
  }

  /// All registered tools.
  public var allTools: [Tool] {
    Array(toolCache.values)
  }

  // MARK: - Validated Tool Handler

  /// Register a tool handler with automatic validation.
  /// Server handles ALL validation - ToolRegistry just parses and executes.
  public func withValidatedToolHandler(
    _ handler: @escaping (CallTool.Params, RequestContext) async throws -> CallTool.Result
  ) {
    withRequestHandler(CallTool.self) { [self] params, ctx in
      let name = params.name

      // Get tool definition for validation
      guard let tool = await self.toolCache[name] else {
        throw MCPError.methodNotFound("Unknown tool: \(name)")
      }

      // Validate input (Server is single source of validation)
      let inputValue: Value = params.arguments.map { .object($0) } ?? .object([:])
      try self.validator.validate(inputValue, against: tool.inputSchema)

      // Execute
      let result: CallTool.Result
      if let registry = await self.toolRegistry,
         await registry.hasTool(name) {
        // DSL tool - registry parses and executes (no validation there)
        result = try await registry.execute(name, arguments: params.arguments)
      } else {
        // Manual tool - call handler
        result = try await handler(params, ctx)
      }

      // Validate output if schema exists (applies to both DSL and manual tools)
      if let outputSchema = tool.outputSchema {
        guard let structured = result.structuredContent else {
          throw MCPError.invalidParams(
            "Tool '\(name)' has outputSchema but returned no structuredContent"
          )
        }
        try self.validator.validate(structured, against: outputSchema)
      }

      return result
    }
  }
}
```

**Usage - Pure DSL:**

```swift
// Define tools
@Tool struct CreateEvent { /* ... */ }
@Tool struct GetEvents { /* ... */ }
@Tool struct DeleteEvent { /* ... */ }

// Create registry and server
let registry = ToolRegistry()
await registry.register(CreateEvent.self)
await registry.register(GetEvents.self)
await registry.register(DeleteEvent.self)

let server = Server(info: impl, capabilities: caps)
await server.registerTools(registry)

// Set up handlers
server.withRequestHandler(ListTools.self) { _, _ in
  ListTools.Result(tools: await server.allTools)
}

server.withValidatedToolHandler { params, ctx in
  // Only reached for non-DSL tools
  throw MCPError.methodNotFound(params.name)
}
```

**Usage - Manual tools:**

```swift
let tools = [
  Tool(name: "search", inputSchema: searchSchema, outputSchema: resultSchema)
]

let server = Server(info: impl, capabilities: caps)
server.registerTools(tools)

server.withRequestHandler(ListTools.self) { _, _ in
  ListTools.Result(tools: await server.allTools)
}

server.withValidatedToolHandler { params, ctx in
  // Input already validated against searchSchema
  switch params.name {
  case "search":
    let result = try await performSearch(params.arguments)
    return result  // Output will be validated against resultSchema
  default:
    throw MCPError.methodNotFound(params.name)
  }
}
```

**Usage - Mixed (DSL + Manual):**

```swift
let registry = ToolRegistry()
await registry.register(CreateEvent.self)

let manualTools = [Tool(name: "legacy_action", inputSchema: legacySchema)]

let server = Server(info: impl, capabilities: caps)
await server.registerTools(registry)
server.registerTools(manualTools)

server.withRequestHandler(ListTools.self) { _, _ in
  ListTools.Result(tools: await server.allTools)
}

server.withValidatedToolHandler { params, ctx in
  switch params.name {
  case "legacy_action":
    return try await handleLegacyAction(params.arguments)
  default:
    throw MCPError.methodNotFound(params.name)
  }
}
```

## Implementation Plan

This will be a PR to the MCP Swift SDK, adding Tool DSL support to the existing `MCP` module.

**Prerequisite:** JSON Schema validator must be implemented first. See `schema-validation/swift-sdk-comparison.md`
for the validator implementation plan.

### Development Setup

1. **Fork and clone the SDK:**
   ```bash
   gh repo fork modelcontextprotocol/swift-sdk --clone
   cd swift-sdk
   git checkout -b tool-dsl
   ```

2. **Add macro target to `Package.swift`:**
   ```swift
   // Add to dependencies:
   .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),

   // Add to targets:
   .macro(
       name: "MCPMacros",
       dependencies: [
           .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
           .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
       ]
   ),

   // Update existing MCP target to depend on macros:
   .target(
       name: "MCP",
       dependencies: ["MCPMacros", ...existing dependencies...]
   ),

   // Add macro tests:
   .testTarget(
       name: "MCPMacroTests",
       dependencies: [
           "MCPMacros",
           .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
       ]
   ),
   ```

3. **Test with apple-mcp during development:**
   ```swift
   // In apple-mcp/Package.swift, temporarily use local path:
   dependencies: [
       .package(path: "../forked/swift-mcp"),
   ],
   ```

4. **When ready, submit PR from fork.**

### Package Structure

Following the SDK's existing pattern of subdirectories within a single module:

```
Sources/
  MCP/
    Base/                    # Existing
    Client/                  # Existing
    Server/                  # Existing
    Extensions/              # Existing
    Validation/              # New - JSON Schema validator
      JSONSchemaValidator.swift   # Protocol + default implementation
    ToolDSL/                 # New directory
      ToolSpec.swift          # Protocol definition
      ToolContext.swift       # Context for progress/logging (wraps RequestHandlerContext)
      ToolOutput.swift        # ToolOutput + StructuredOutput protocols
      Parameter.swift        # @Parameter property wrapper + ParameterValue conformances
      AnnotationOption.swift # Annotation enum
      ToolEnum.swift          # Enum protocol
      ToolRegistry.swift     # Registration and execution with validation
  MCPMacros/                 # Macros must be separate target
    ToolMacro.swift          # @Tool macro implementation
    OutputSchemaMacro.swift  # @OutputSchema macro implementation
    Diagnostics.swift        # Compile-time error messages
```

Users import just `MCP`—no separate module for the DSL.

### Phase 0: JSON Schema Validator (Prerequisite)
- Implement `JSONSchemaValidator` protocol wrapping [swift-json-schema](https://github.com/ajevans99/swift-json-schema)
- Build `DefaultJSONSchemaValidator` using the `JSONSchema` module (no swift-syntax dependency)
- Add `Value.toJSONValue()` conversion for validation boundary
- Add Server tool cache and `withValidatedToolHandler`
- Add elicitation response validation
- See `schema-validation/swift-sdk-comparison.md` for details

### Phase 1: Core Macro Infrastructure
- `@Tool` macro that generates:
  - `toolDefinition` with JSON Schema (`inputSchema`)
  - `parse(from:)` for type conversion (no validation code)
  - `ToolSpec` protocol conformance
- `@Parameter` property wrapper
- Basic types: `String`, `Int`, `Double`, `Bool`
- `ToolOutput` protocol with `String` conformance

### Phase 2: Extended Types
- `Date` parameter with ISO 8601 parsing
- Optional parameter handling (`T?`)
- Default value support
- Array parameters (`[T]`)
- `ToolEnum` protocol for type-safe enums

### Phase 3: Registry Integration
- `ToolRegistry` with validator integration
- Server `registerTools()` methods
- Result builder for tool grouping
- Integration with `withValidatedToolHandler`

### Phase 4: Output Schema Support
- `@OutputSchema` macro for output types
- `StructuredOutput` protocol
- Automatic `outputSchema` detection in `toolDefinition` via runtime type check
- Output validation in Server (not ToolRegistry)

### Phase 5: Documentation & Examples
- Comprehensive DocC documentation
- Migration guide from manual registration
- Example tools in SDK
- Integration examples (pure DSL, manual, mixed)

## Macro Expansion

The `@Tool` macro generates protocol conformance and parsing code, similar to how
App Intents' internal code generation works.

**Key difference from typical macro patterns:** The macro does NOT generate validation code.
All validation is handled by `JSONSchemaValidator` at runtime. The generated `parse(from:)`
method assumes validation has already passed and can safely convert types.

### Input (Developer writes)

```swift
@Tool
struct CreateCalendarEvent {
  static let name = "create_calendar_event"
  static let description = "Create a new calendar event"

  @Parameter(description: "The title of the event", maxLength: 500)
  var title: String

  @Parameter(key: "start_date", description: "Start date/time in ISO 8601 format")
  var startDate: Date

  @Parameter(key: "end_date", description: "End date. Defaults to 1 hour after start.")
  var endDate: Date?

  func perform() async throws -> String {
    try await CalendarEvents.createEvent(
      title: title,
      startDate: startDate,
      endDate: endDate
    )
  }
}
```

### Output (Macro generates)

```swift
struct CreateCalendarEvent: ToolSpec {
  typealias Output = String

  static let name = "create_calendar_event"
  static let description = "Create a new calendar event"

  @Parameter(description: "The title of the event", maxLength: 500)
  var title: String

  @Parameter(key: "start_date", description: "Start date/time in ISO 8601 format")
  var startDate: Date

  @Parameter(key: "end_date", description: "End date. Defaults to 1 hour after start.")
  var endDate: Date?

  func perform(context: ToolContext) async throws -> String {
    try await CalendarEvents.createEvent(
      title: title,
      startDate: startDate,
      endDate: endDate
    )
  }

  // MARK: - Generated by @Tool macro

  init() {}

  static var toolDefinition: Tool {
    Tool(
      name: name,
      description: description,
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "title": .object([
            "type": .string("string"),
            "description": .string("The title of the event"),
            "maxLength": .int(500)
          ]),
          "start_date": .object([
            "type": .string("string"),
            "format": .string("date-time"),
            "description": .string("Start date/time in ISO 8601 format")
          ]),
          "end_date": .object([
            "type": .string("string"),
            "format": .string("date-time"),
            "description": .string("End date. Defaults to 1 hour after start.")
          ])
        ]),
        "required": .array([.string("title"), .string("start_date")])
      ]),
      // Output schema auto-detected: nil if Output doesn't conform to StructuredOutput
      outputSchema: (Output.self as? StructuredOutput.Type)?.schema,
      annotations: Self.buildAnnotations()
    )
  }

  private static func buildAnnotations() -> Tool.Annotations {
    var a = Tool.Annotations()
    for option in Self.annotations {
      switch option {
      case .readOnly:
        a.readOnlyHint = true
        a.destructiveHint = false
        a.idempotentHint = true
      case .idempotent:
        a.idempotentHint = true
      case .closedWorld:
        a.openWorldHint = false
      case .title(let t):
        a.title = t
      }
    }
    return a
  }

  /// Parse validated arguments into a typed instance.
  /// Uses defensive guards - throws clear errors if parsing fails.
  static func parse(from arguments: [String: Value]?) throws -> Self {
    var instance = Self()
    let args = arguments ?? [:]

    // Required parameters - validation should guarantee these exist
    guard let titleValue = args["title"], let title = String(titleValue) else {
      throw MCPError.internalError("Parse failed for 'title' - validation should have caught this")
    }
    instance.title = title

    guard let startDateValue = args["start_date"], let startDate = Date(startDateValue) else {
      throw MCPError.internalError("Parse failed for 'start_date' - validation should have caught this")
    }
    instance.startDate = startDate

    // Optional parameters
    instance.endDate = args["end_date"].flatMap { Date($0) }

    return instance
  }
}
```

**Throwing instead of crashing:** The `parse(from:)` method uses guard statements that
throw recoverable errors rather than force unwraps that would crash. This:
- Aligns with Python/TypeScript behavior (errors, not crashes)
- Keeps the server running if there's a bug in validation or schema generation
- Provides clear error messages indicating what went wrong
- Makes the error catchable by `ToolRegistry` which returns it as `CallTool.Result(isError: true)`

If parsing fails despite validation, the error message indicates a bug that should be fixed,
but the server stays up and clients receive a proper error response.

### Key Macro Responsibilities

1. **Add `ToolSpec` conformance** - Protocol conformance for registry
2. **Generate `typealias Output`** - Inferred from `perform()` return type
3. **Generate `init()`** - Empty initializer to satisfy protocol requirement (users don't write this)
4. **Generate `toolDefinition`** - Static computed property returning `Tool` with:
   - `name` and `description` from developer's static properties
   - `inputSchema` derived from `@Parameter` properties (using `key:` if specified, otherwise property name)
   - `outputSchema` via runtime type check: `(Output.self as? StructuredOutput.Type)?.schema`
   - `annotations`: converts `[AnnotationOption]` to `Tool.Annotations`
5. **Generate `parse(from:)`** - Static method that:
   - Converts `[String: Value]?` into typed properties using `init?(_:)`
   - Uses guard statements with throwing errors (not force unwraps)
   - Creates instance via `init()` and populates properties
   - Throws `MCPError.internalError` if parsing fails (indicates validation bug)
6. **Emit compile-time diagnostics** for:
   - Non-literal default values (expressions like `Date()` cannot be evaluated)
   - Missing required static properties (`name`, `description`)
   - Invalid `@Parameter` usage
   - Duplicate annotations (error)
   - Redundant annotations like `.idempotent` with `.readOnly` (warning)
7. **Validate tool name at compile time** (since only string literals are accepted):
   - Error if name is empty or exceeds 128 characters
   - Error if name contains invalid characters (only A-Z, a-z, 0-9, `_`, `-`, `.` allowed)
   - Warning if name starts/ends with `-` or `.`
   - This catches issues earlier than runtime validation in `ToolNameValidation.swift`

**What the macro does NOT generate:**
- Validation code (handled by `JSONSchemaValidator`)
- Error messages for invalid arguments (handled by validator)
- Constraint checking (minLength, maxLength, etc. - handled by validator)

## Comparison with App Intents

| Feature | App Intents | MCP Tools DSL |
|---------|-------------|---------------|
| Conformance | `struct X: AppIntent` | `@Tool struct X` |
| Protocol | `AppIntent` | `ToolSpec` |
| Name | `static var title: LocalizedStringResource` | `static let name: String` |
| Description | `static var description: IntentDescription` | `static let description: String` |
| Parameters | `@Parameter(title:)` | `@Parameter(description:)` |
| Execution | `func perform() -> some IntentResult` | `func perform(context:) -> Output` |
| Context | N/A (system provides) | `ToolContext` (progress, logging) |
| Enums | `AppEnum` | `ToolEnum` |
| Hints | `static var openAppWhenRun: Bool` | `static let annotations: [AnnotationOption]` |

**Design alignment:**

| Aspect | App Intents | MCP Tools DSL | Match? |
|--------|-------------|---------------|--------|
| Static metadata properties | ✓ | ✓ | ✅ |
| `@Parameter` property wrapper | ✓ | ✓ | ✅ |
| `perform()` async throws | ✓ | `perform(context:)` | ✅ |
| Context for notifications | System-provided | `ToolContext` | ✅ |
| Protocol-based registration | ✓ | ✓ | ✅ |
| Enum support | `AppEnum` | `ToolEnum` | ✅ |
| Code generation | Internal compiler | Swift macro | ✅ |

**Key differences:**
- App Intents uses internal compiler magic; MCP uses Swift 5.9 macros (same effect)
- App Intents uses `LocalizedStringResource`; MCP uses plain `String` (no localization needed)
- App Intents returns `some IntentResult`; MCP returns concrete `Output` type (enables output schema support)
- App Intents hints are individual properties; MCP uses `[AnnotationOption]` array (converted to `Tool.Annotations` by macro)
- App Intents uses `@Parameter(title:)` for human-readable UI labels; MCP uses `@Parameter(description:)` to match JSON Schema's `description` field (LLM-facing, not user-facing)
- App Intents validates internally; MCP delegates to `JSONSchemaValidator` (shared with manual tools)

## MCP SDK Compatibility

The DSL generates code that integrates directly with the MCP Swift SDK types.

### Generated `Tool` Instance

For this DSL definition:
```swift
@Tool
struct CreateCalendarEvent {
  static let name = "create_calendar_event"
  static let description = "Create a new calendar event"

  @Parameter(description: "The title of the event")
  var title: String

  @Parameter(key: "start_date", description: "Start date/time in ISO 8601 format")
  var startDate: Date

  @Parameter(description: "Location of the event")
  var location: String?

  func perform() async throws -> some ToolResult { ... }
}
```

The `@Tool` macro generates this `Tool` definition:
```swift
Tool(
  name: "create_calendar_event",
  description: "Create a new calendar event",
  inputSchema: .object([
    "type": .string("object"),
    "properties": .object([
      "title": .object([
        "type": .string("string"),
        "description": .string("The title of the event")
      ]),
      "start_date": .object([
        "type": .string("string"),
        "description": .string("Start date/time in ISO 8601 format")
      ]),
      "location": .object([
        "type": .string("string"),
        "description": .string("Location of the event")
      ])
    ]),
    "required": .array([.string("title"), .string("start_date")])
  ]),
  annotations: Tool.Annotations(
    title: nil,
    readOnlyHint: nil,
    destructiveHint: nil,
    idempotentHint: nil,
    openWorldHint: nil
  )
)
```

### Validation Flow

Server is the single source of validation (matching Python/TypeScript SDKs):

```
┌──────────────────────────────────────────────────────────────────┐
│              Server.withValidatedToolHandler()                    │
├──────────────────────────────────────────────────────────────────┤
│ 1. Validate input (Server)                                        │
│    validator.validate(arguments, against: tool.inputSchema)       │
│    - Checks required fields                                       │
│    - Validates types (string, integer, etc.)                      │
│    - Enforces constraints (minLength, maximum, enum, etc.)        │
│    - Throws MCPError.invalidParams on failure                     │
├──────────────────────────────────────────────────────────────────┤
│ 2. Execute tool                                                   │
│    ┌─────────────────────────────────────────────────────────┐    │
│    │ DSL Tool → ToolRegistry.execute()                       │    │
│    │   - Parse: let instance = try parse(from: arguments)    │    │
│    │   - Execute: let output = try await instance.perform()  │    │
│    │   - Return: output.toCallToolResult()                   │    │
│    ├─────────────────────────────────────────────────────────┤    │
│    │ Manual Tool → handler(params, ctx)                      │    │
│    └─────────────────────────────────────────────────────────┘    │
├──────────────────────────────────────────────────────────────────┤
│ 3. Validate output (Server, if outputSchema exists)               │
│    validator.validate(result.structuredContent, against: schema)  │
│    - Ensures structured output matches declared schema            │
├──────────────────────────────────────────────────────────────────┤
│ 4. Any error → CallTool.Result(isError: true)                     │
│    - Server stays up, client receives error response              │
│    - Aligns with Python/TypeScript behavior                       │
└──────────────────────────────────────────────────────────────────┘
```

See the [Macro Expansion](#macro-expansion) section for the generated `parse(from:)` code.

### Type Mapping: Swift → JSON Schema

| Swift Type | JSON Schema `type` | Notes |
|------------|-------------------|-------|
| `String` | `"string"` | Supports `minLength`, `maxLength` |
| `Int` | `"integer"` | Supports `minimum`, `maximum` |
| `Double` | `"number"` | Supports `minimum`, `maximum` |
| `Bool` | `"boolean"` | |
| `Date` | `"string"` | Parsed as ISO 8601 |
| `Data` | `"string"` | Base64 encoded (data URL format) |
| `T?` | Same as `T` | Not in `required` array |
| `[T]` | `"array"` | With `items` schema |
| `ToolEnum` | `"string"` | With `enum` array |

**Validation constraints in schema:**
```swift
@Parameter(description: "Title", minLength: 1, maxLength: 500)
var title: String

// Generates:
"title": .object([
  "type": .string("string"),
  "description": .string("Title"),
  "minLength": .int(1),
  "maxLength": .int(500)
])
```

Note: The MCP SDK's `Value` type has a `.data(mimeType: String?, Data)` case that
automatically handles data URL encoding/decoding. This could be useful for tools
that accept or return binary data (images, files, etc.).

### Value Parsing: MCP SDK → Swift

The SDK provides convenience initializers for converting `Value` to Swift types:

| Target Type | Initializer | Notes |
|-------------|-------------|-------|
| `String` | `String(_: Value)` | Returns nil if not a string |
| `Int` | `Int(_: Value)` | Returns nil if not an integer |
| `Double` | `Double(_: Value)` | Returns nil if not a number |
| `Bool` | `Bool(_: Value)` | Returns nil if not a boolean |
| `Date` | `Date(_: Value)` | Parses ISO 8601 string |
| `[T]` | `Array.init(_: Value)` | Maps array elements |

**DSL parsing approach:**

The generated `parse(from:)` uses guard statements with throwing errors:

```swift
static func parse(from arguments: [String: Value]?) throws -> Self {
    var instance = Self()
    let args = arguments ?? [:]

    // Required fields - validation should guarantee these exist
    guard let titleValue = args["title"], let title = String(titleValue) else {
        throw MCPError.internalError("Parse failed for 'title' - validation should have caught this")
    }
    instance.title = title

    guard let startDateValue = args["start_date"], let startDate = Date(startDateValue) else {
        throw MCPError.internalError("Parse failed for 'start_date' - validation should have caught this")
    }
    instance.startDate = startDate

    // Optional fields
    instance.location = args["location"].flatMap { String($0) }

    return instance
}
```

**Why throwing instead of force unwraps:**
1. **Server stays up** - Parse failure returns error response, doesn't crash
2. **Aligns with Python/TypeScript** - They throw catchable exceptions, not fatal crashes
3. **Clear error messages** - Indicates which field failed and that it's a validation bug
4. **Defensive coding** - Safe even if validation is accidentally skipped

If parsing fails despite validation, the error indicates a bug in the validator or schema
generation that should be fixed, but the server remains operational.

### Annotation Implicit Defaults

When `Tool.Annotations` fields are `nil`, the MCP spec defines implicit defaults:

| Field | Implicit Default (when `nil`) | Meaning |
|-------|------------------------------|---------|
| `readOnlyHint` | `false` | Tool may modify state |
| `destructiveHint` | `true` | Tool may destroy data |
| `idempotentHint` | `false` | Repeated calls may have effects |
| `openWorldHint` | `true` | Tool interacts with external world |

Our DSL converts `[AnnotationOption]` to `Tool.Annotations`, setting explicit values only when
specified. An empty array results in all `nil` fields (MCP implicit defaults apply).

### Error Handling

The SDK provides `MCPError` for JSON-RPC errors:

**Validation errors (from JSONSchemaValidator):**
```swift
// Thrown by validator when arguments don't match schema
throw MCPError.invalidParams("'title' is required")
throw MCPError.invalidParams("'limit' must be at least 1")
throw MCPError.invalidParams("'status' must be one of: pending, active, completed")
```

**Execution errors (from tool's perform()):**
```swift
// Tools throw domain-specific errors
throw MCPError.internalError("Failed to create event: \(error)")
throw CalendarError.eventNotFound(id)  // Caught and wrapped by ToolRegistry
```

The `ToolRegistry.execute()` method catches errors from `perform()` and converts
them to `CallTool.Result(isError: true)` with appropriate error messages.

### Tool List Changed Notification

The SDK supports `ToolListChangedNotification` for dynamic tool updates:
```swift
public struct ToolListChangedNotification: Notification {
  public static let name: String = "notifications/tools/list_changed"
}
```

If our DSL supports runtime tool registration/removal, we should send this notification.
For static tool sets (current design), this isn't needed.

## Design Decisions

1. **Key Naming**
   - Property name is used as-is in schema by default
   - Use `key:` parameter to specify a different JSON key: `@Parameter(key: "start_date", description: "...")`
   - No automatic camelCase → snake_case conversion (explicit is better than magic)
   - Follows the same pattern as MLX Swift and Codable's `CodingKeys`

2. **Validation Strategy**
   - **Single source of truth:** `JSONSchemaValidator` handles ALL validation
   - DSL constraints (`minLength`, `maxLength`, `minimum`, `maximum`) go into schema only
   - DSL does NOT generate validation code—validator enforces everything
   - This ensures DSL tools and manual tools have identical validation behavior
   - See `schema-validation/swift-sdk-comparison.md` for validator implementation

3. **Error Handling**
   - `JSONSchemaValidator` throws `MCPError.invalidParams` for all validation failures
   - Validator produces clear, consistent error messages
   - Domain errors from `perform()` are caught by `ToolRegistry` and wrapped in `CallTool.Result(isError: true)`
   - No error message generation in DSL macro—simplifies macro and ensures consistency

4. **Defensive Parsing with Throwing Errors**
   - `parse(from:)` uses guard statements with throwing errors (not force unwraps)
   - Aligns with Python/TypeScript which throw catchable exceptions
   - Server stays up on parse failure, returns error response to client
   - Parsing failures indicate schema/validator bugs but don't crash the server

5. **Module Structure**
   - Tool DSL lives in `MCP/ToolDSL/` directory within the existing `MCP` module
   - JSON Schema validator lives in `MCP/Validation/`
   - Follows SDK's existing pattern of subdirectories for logical grouping
   - Separate `MCPMacros` target for Swift macro implementations (required by Swift)
   - Users import just `MCP`—no separate module needed

6. **Async Context**
   - No default actor isolation on `perform()`
   - Implementers add `@MainActor` when needed (e.g., Apple framework access)
   - Example: `@MainActor func perform() async throws -> String`

7. **Nested Object Parameters**
   - Custom structs as parameters are **not supported** in the initial implementation
   - This matches App Intents, which primarily uses primitives and entities
   - For complex inputs, developers should either:
     - Flatten to separate parameters: `locationLat: Double`, `locationLng: Double`
     - Accept a JSON string and parse in `perform()`: `locationJson: String`
   - Rationale: Nested objects require complex macro logic for schema generation and
     recursive parsing. The added complexity isn't justified for v1 when workarounds exist.
   - Future consideration: A `NestedParameter` protocol could enable opt-in support

8. **Annotations as Array**
   - Annotations use `[AnnotationOption]` array syntax instead of fluent builders
   - Each option is independent: `[.readOnly, .title("List Events")]`
   - No `.destructive` case—it's the MCP implicit default; omitting `.readOnly` implies destructive
   - Protocol provides default empty array, so `annotations` can be omitted entirely
   - Macro validates at compile time:
     - Errors for duplicates (e.g., two `.title(...)` values)
     - Warnings for redundancy (e.g., `.idempotent` with `.readOnly`)
   - Rationale: Array syntax is simpler than fluent chaining, avoids contradictory states,
     and works naturally with Swift's type inference when the protocol declares the type

9. **Output Schema Support**
   - Single `@Tool` macro with automatic output schema detection (aligns with TypeScript/Python)
   - `@OutputSchema` macro generates `schema` property for output types
   - Runtime type check: `(Output.self as? StructuredOutput.Type)?.schema`
   - Returns `nil` for simple types like `String`, returns schema for `StructuredOutput` types
   - Server validates output against schema if present (not ToolRegistry)
   - All encoding/conversion failures throw errors - server never crashes

10. **ToolContext (TypeScript-style)**
    - `perform(context: ToolContext)` always receives context (like TypeScript's `extra` parameter)
    - Python uses opt-in via type hints; Swift can't easily do this without complex macro logic
    - `ToolContext` wraps `RequestHandlerContext` with tool-friendly API:
      - `reportProgress(_:total:message:)` - Progress notifications (auto-handles missing token)
      - `info(_:)`, `debug(_:)`, `warning(_:)`, `error(_:)` - Logging
      - `isCancelled`, `checkCancellation()` - Cancellation support
    - Tools that don't need context simply ignore the parameter
    - Created internally by Server/ToolRegistry - users never construct it

11. **Cancellation**
    - Uses Swift's native cooperative cancellation (not a custom signal)
    - `context.isCancelled` - Check if request was cancelled
    - `context.checkCancellation()` - Throws `CancellationError` if cancelled
    - Long-running tools should check cancellation at appropriate points
    - Server catches `CancellationError` and returns appropriate error response
    - TypeScript uses `AbortSignal`; Swift's `Task` cancellation is idiomatic equivalent

12. **ToolRegistry Synchronous Init**
    - Result builder initializer is synchronous despite ToolRegistry being an actor
    - Actor init can be synchronous when it only stores data (no async operations)
    - We only store tool types, not instances - no async work needed
    - This enables clean syntax: `ToolRegistry { Tool1.self; Tool2.self }`
    - `register()` method is async for dynamic registration after init

13. **Parameter Descriptions Are Optional**
    - `@Parameter(description:)` is optional, matching Python and TypeScript SDK behavior
    - Python: `Field(description=...)` is optional
    - TypeScript: Zod `.describe()` is optional
    - No compile-time warning for missing descriptions
    - Rationale: Parity with other SDKs; neither Python nor TypeScript warn about missing descriptions

14. **Compile-Time Tool Name Validation**
    - The `@Tool` macro validates `static let name = "..."` at compile time
    - Only string literals are accepted (expressions like `someVariable` emit an error)
    - Validation rules match `ToolNameValidation.swift`:
      - Length: 1-128 characters
      - Characters: A-Z, a-z, 0-9, `_`, `-`, `.`
      - Warnings for leading/trailing `-` or `.`
    - Catches invalid names at build time rather than runtime
    - Runtime validation in `ToolNameValidation.swift` remains as fallback for manual tools

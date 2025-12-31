# Deferred Features

Features that may be added to the high-level API based on future demand. These are intentionally excluded from the initial implementation to keep scope focused.

## Deferred for High-Level API

### 1. Completion/Autocomplete Support

**What it is:** TypeScript and Python SDKs support completions for resource template variables and prompt arguments. This allows interactive UIs to provide autocomplete suggestions as users type.

**Why deferred:** Most Swift MCP servers will be used with LLM clients (like Claude) that don't use autocomplete - they invoke tools/prompts directly with full arguments. This feature is primarily useful for:
- Interactive CLI tools
- GUI-based MCP clients with input fields
- IDE integrations

**Implementation notes:** When needed, this would involve:
- `Completable` wrapper for schemas (similar to TypeScript)
- Completion handlers for resource templates and prompt arguments
- Integration with `ResourceRegistry` and `PromptRegistry`

**Reference:** TypeScript's `Completable` in `@modelcontextprotocol/server`, Python's `completion()` decorator in FastMCP.

---

### 2. High-Level Tasks API Convenience

**What it is:** The experimental Tasks API allows long-running tool operations to execute asynchronously, returning a task ID that clients can poll for progress/completion.

**Current state:** Fully implemented at the low-level in `Sources/MCP/Server/Experimental/Tasks/`. Users can access it via:
```swift
// Access low-level task support through the underlying server
server.server.enableTaskSupport(TaskSupport.inMemory())
```

**Why deferred:** The low-level API provides full functionality. High-level convenience methods would be syntactic sugar:
```swift
// Potential future API
server.enableTaskSupport()
server.registerTask("long-operation") { args, ctx in ... }
```

**Implementation notes:** When needed, add convenience methods to `MCPServer` that delegate to the underlying `Server`.

---

### 3. Server Composition/Mounting

**What it is:** Python's FastMCP supports mounting multiple MCP servers in a single HTTP application via `session_manager`.

**Why deferred:** This is an advanced use case for:
- Microservice-style architecture with specialized MCP servers
- Multi-tenant deployments
- Modular server design

Most deployments will have a single MCP server. Users needing composition can access the underlying `Server` and transports directly.

**Implementation notes:** When needed, consider a `CompositeServer` or routing layer that delegates to multiple `MCPServer` instances.

---

### 4. Framework App Generation

**What it is:** Python's FastMCP can generate ASGI applications via `streamable_http_app()` for integration with web frameworks.

**Why deferred:** The current `TransportType.http` approach handles standalone HTTP servers. Framework integration (SwiftNIO, Hummingbird, Vapor) may need different patterns.

**Implementation notes:** When needed, consider:
```swift
// Potential future API
let app = server.asHummingbirdApp()
let handler = server.asRequestHandler()  // For custom integration
```

---

### 5. Custom HTTP Routes

**What it is:** Python's FastMCP has `@custom_route()` for adding non-MCP endpoints (health checks, OAuth callbacks, metrics) alongside the MCP server.

**Why deferred:** This is a transport-level concern, not a high-level MCP API concern. The `MCPServer` abstraction should remain transport-agnostic.

**Current alternative:** Users who need custom HTTP routes can:
1. Use an HTTP framework (Hummingbird, Vapor) directly
2. Integrate MCP as one route handler among others
3. Access the low-level transport for custom integration

**Implementation notes:** If demand warrants, this would be added at the HTTP transport layer, not the high-level `MCPServer` API.

---

### 6. HttpResource (URL-backed Resource)

**What it is:** Python's FastMCP provides `HttpResource` for proxying content from a URL as an MCP resource.

**Why deferred:** HTTP fetching introduces complexity that may not be appropriate for a simple built-in type:
- Redirect handling
- Authentication headers
- Timeout configuration
- Caching policies
- Error handling for network failures
- Streaming vs. buffered responses

**Current alternative:** Users can implement URL-backed resources using `FunctionResource`:
```swift
FunctionResource(
    uri: "proxy://example",
    name: "example_data",
    mimeType: "application/json"
) {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.example.com/data")!)
    return .binary(data, uri: "proxy://example", mimeType: "application/json")
}
```

**Implementation notes:** If demand warrants, consider a configurable `URLResource` with options for timeout, headers, and caching.

---

### 7. Resource Access from Handlers

**What it is:** Python's `Context` provides `read_resource(uri)` allowing tools to read other registered resources.

**Why deferred:** This is an advanced use case for tools that need to compose data from multiple resources. Most tools operate independently.

**Current alternative:** Tools can access resources through application-level dependency injection:
```swift
let resourceManager = MyResourceManager()
await server.register(name: "analyze", description: "Analyze data") { (args: AnalyzeArgs, ctx) in
    let data = try await resourceManager.getData()  // Captured in closure
    return analyze(data)
}
```

**Implementation notes:** When needed, add `readResource(_:)` to `HandlerContext`. This requires the context to hold a reference to the server or resource registry.

---

### 8. Full RFC 6570 URI Template Parsing

**What it is:** RFC 6570 defines a standard for URI templates with operators for different expansion behaviors:

| Operator | Example | Expansion |
|----------|---------|-----------|
| None | `{var}` | `value` |
| `+` | `{+var}` | `value` (reserved chars allowed) |
| `#` | `{#var}` | `#value` (fragment) |
| `.` | `{.var}` | `.value` (label) |
| `/` | `{/var}` | `/value` (path segment) |
| `?` | `{?var}` | `?var=value` (query) |
| `&` | `{&var}` | `&var=value` (query continuation) |

Plus: array values, exploded form (`{var*}`), prefix modifiers (`{var:3}`), and proper percent-encoding.

**Current approach:** The `ResourceTemplate` matching uses simple regex conversion (`{variable}` → `(?<variable>[^/]+)`), following Python's approach. This handles basic path variables.

**Why deferred:** Real-world MCP resource templates are simple:
```
file:///{path}
db://tables/{table}
config://{section}/{key}
```

RFC 6570 operators (`+`, `?`, `#`, etc.) are rare in practice. The simple regex approach covers 99% of use cases.

**Reference implementations:**
- **TypeScript SDK** (`uriTemplate.ts`): Full RFC 6570 implementation (~500 lines) supporting both `expand(variables)` and `match(uri)`. Includes security limits (1MB max template, 10,000 max expressions).
- **Python SDK** (`templates.py`): Simple regex approach like our planned implementation.
- **Existing Swift packages**: [nicklockwood/URITemplate](https://github.com/nicklockwood/URITemplate) provides expansion only, not matching.

**Implementation notes:** If demand warrants, port TypeScript's approach since it uniquely supports both expansion and matching:
```swift
public struct URITemplate: Sendable {
    public enum Operator: Character, Sendable {
        case none = "\0"
        case reserved = "+"
        case fragment = "#"
        case label = "."
        case pathSegment = "/"
        case query = "?"
        case queryContinuation = "&"
    }

    private let parts: [Part]  // Literal or Expression

    /// Generate a URI from template and variables
    public func expand(_ variables: [String: Any]) -> String

    /// Extract variables from a URI (reverse of expansion)
    public func match(_ uri: String) -> [String: String]?
}
```

Key implementation considerations:
- Security limits to prevent ReDoS attacks
- Named capture groups for variable extraction
- Proper percent-encoding/decoding per operator rules
- Support for array values and exploded form

---

### 9. Logging for Registration Operations

**What it is:** Log tool/resource/prompt registration, enable/disable, and removal operations for debugging and observability.

**Why deferred:** The `Server` logger is tied to the transport connection, which may not exist when registration happens (tools are often registered before connection). Adding a separate logger would require new infrastructure.

**Current alternative:** Developers can add their own logging around registration calls in their application code.

**Implementation notes:** If demand warrants, consider:
- Adding an optional `Logger` parameter to `MCPServer` initializer
- Using `os.Logger` for system-integrated logging
- Logging at debug level to avoid noise in production

---

## Out of Scope (Planned Elsewhere)

### OAuth/Auth Integration

**What it is:** Python has full auth settings with `auth_server_provider`, `token_verifier`, and middleware. TypeScript has middleware support for auth.

**Why out of scope:** Authentication is being planned separately as part of HTTP transport work. It's a transport-level concern, not a high-level API concern.

**Tracking:** See HTTP transport planning documents for auth implementation plans.

---

## Won't Implement

### Environment-Based Settings

**What it is:** Python's FastMCP has a `Settings` class that reads configuration from `FASTMCP_*` environment variables.

**Why not implementing:** Not idiomatic for Swift applications. Swift developers typically use:
- `ArgumentParser` for command-line configuration
- Configuration files (plist, JSON, YAML)
- Xcode schemes for per-environment settings
- Direct initialization in code

Users who need environment-based configuration can implement it in their application layer.

---

### `@Resource` and `@Prompt` Macros

**What it is:** Similar to `@Tool` macro, but for resource and prompt definitions.

**Why not implementing:** Neither Python nor TypeScript uses type-based definitions for resources/prompts. They all use callback/decorator patterns. The closure-based registration in Swift plans is sufficient and matches other SDKs:
```swift
server.registerResource("config", uri: "file:///config.json") { uri, ctx in ... }
server.registerPrompt("summarize") { args, ctx in ... }
```

Macros would add complexity without proportional benefit.

---

### `@ResourceBuilder` and `@PromptBuilder`

**What it is:** Result builders for batch registration of resources/prompts, similar to `@ToolBuilder`.

**Why not implementing:** Neither Python nor TypeScript has batch registration for resources/prompts. Individual registration via closures is sufficient. `@ToolBuilder` works well for type-based tool registration, but resources/prompts use callback-based registration where result builders add little value.

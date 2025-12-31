# Documentation Evolution Plan

Plan for updating documentation once high-level convenience APIs are implemented.

## Context

The Swift SDK currently provides only low-level APIs. Documentation shows manual patterns:
- `withRequestHandler` for all request types
- Manual JSON Schema construction for tools
- Manual switch statements for routing in CallTool handlers
- Separate ListTools and CallTool handler registration

Once the high-level APIs are implemented (see `mcp-tool-dsl-design.md`), the documentation needs to evolve to:
1. Lead with high-level APIs for most users
2. Preserve low-level documentation for advanced use cases

## Guiding Principles

- **Lead with simplicity**: New users should see the easiest path first
- **Don't hide complexity**: Low-level APIs are valuable for debugging, customization, and understanding
- **Feature-centric organization**: All "tools" content in one place, not split across sections
- **Progressive disclosure**: High-level first, low-level in "Advanced" sections
- **Match other SDKs**: Python and TypeScript docs lead with their high-level APIs (FastMCP, McpServer)

## Structure Decision

**Keep the current documentation structure unchanged.** No new top-level sections needed.

```
Getting Started
Client Guide
├── Setup
├── Tools
├── Resources
├── Prompts
├── Completions
├── Sampling
├── Elicitation
├── Roots
├── Tasks
├── Advanced
Server Guide
├── Setup
├── Tools
├── Resources
├── Prompts
├── Completions
├── Sampling
├── Elicitation
├── Roots
├── Tasks
├── Advanced
Transports
Debugging
```

## What Changes

### 1. Feature Articles Show High-Level First

**Server Tools (server-tools.md)**

Before (current):
```swift
await server.withRequestHandler(ListTools.self) { _, _ in
    ListTools.Result(tools: [
        Tool(
            name: "weather",
            description: "Get weather",
            inputSchema: [
                "type": "object",
                "properties": [
                    "location": ["type": "string"]
                ],
                "required": ["location"]
            ]
        )
    ])
}

await server.withRequestHandler(CallTool.self) { params, _ in
    switch params.name {
    case "weather":
        // ...
    default:
        throw MCPError.invalidParams("Unknown tool")
    }
}
```

After (high-level first):
```swift
@Tool
struct Weather {
    static let name = "weather"
    static let description = "Get weather for a location"

    @Parameter(description: "City name")
    var location: String

    func perform(context: ToolContext) async throws -> String {
        // ...
    }
}

// Register with server
let registry = ToolRegistry {
    Weather.self
}
await server.registerTools(registry)
```

Similar changes for:
- **server-resources.md** - High-level resource registration
- **server-prompts.md** - High-level prompt registration

### 2. Advanced Articles Expand to Include Low-Level Patterns

**Server Advanced (server-advanced.md)**

Current content (keep):
- Request Handler Context
- Progress notifications
- Logging
- Cancellation handling
- HTTP transport considerations
- Graceful shutdown

New content to add:
- Manual request handler patterns
- Manual tool registration (JSON Schema, ListTools, CallTool routing)
- Manual resource registration
- Manual prompt registration
- Mixing DSL tools with manual tools
- When to use low-level vs high-level

**Client Advanced (client-advanced.md)**

Current content (keep):
- Request timeouts
- Progress tracking
- Cancellation
- Concurrent requests

New content to add:
- Low-level `send()` method
- Direct Request/Response types
- Notification handlers (`onNotification`)
- Manual capability checking

### 3. Getting Started Uses High-Level Only

The getting-started.md example should use DSL for the server:

```swift
@Tool
struct Greet {
    static let name = "greet"
    static let description = "Greet someone by name"

    @Parameter(description: "Name to greet")
    var name: String

    func perform(context: ToolContext) async throws -> String {
        "Hello, \(name)!"
    }
}

let registry = ToolRegistry {
    Greet.self
}

let server = Server(name: "MyServer", version: "1.0.0", capabilities: .init(tools: .init()))
await server.registerTools(registry)

// ... rest of example
```

## Splitting Advanced Into a Subsection (If Needed)

If the Advanced article becomes too long, convert it into a subsection with multiple articles:

```
Server Guide
├── Setup
├── Tools
├── Resources
├── Prompts
├── ...
├── Advanced                       ← Becomes a subsection
│   ├── Request Context            (progress, logging, cancellation)
│   ├── Manual Registration        (tools, resources, prompts without DSL)
│   ├── HTTP Considerations        (sessions, auth, multi-client)

Client Guide
├── ...
├── Advanced                       ← Becomes a subsection (if needed)
│   ├── Timeouts and Cancellation
│   ├── Low-Level Requests         (send(), raw types, notifications)
```

This keeps advanced content grouped logically without creating new top-level sections.

**When to split:** If the combined article exceeds ~400-500 lines or becomes hard to navigate. Start with one article and evaluate.

## Migration Checklist

When high-level APIs are ready:

- [ ] Update getting-started.md to use DSL
- [ ] Rewrite server-tools.md (DSL primary, link to Advanced for manual)
- [ ] Rewrite server-resources.md (high-level primary)
- [ ] Rewrite server-prompts.md (high-level primary)
- [ ] Expand server-advanced.md with manual registration patterns
- [ ] Expand client-advanced.md with low-level send() patterns
- [ ] Update server-setup.md to show ToolRegistry integration
- [ ] Review all code examples for consistency
- [ ] Add "See Advanced for manual approach" links where appropriate
- [ ] Evaluate if server-advanced.md needs splitting

## Non-Goals

- No new top-level documentation sections
- No separate "Low-Level API Reference" section
- No splitting features across multiple articles (e.g., "Tools" and "Tools Advanced")
- No hiding low-level APIs entirely

## Dependencies

This documentation update depends on:
1. Tool DSL implementation (`mcp-tool-dsl-design.md`)
2. JSON Schema validator implementation
3. ToolRegistry implementation
4. Server integration with registry

Documentation updates should happen alongside or immediately after the API implementation.

# High-Level API Comparison: TypeScript, Python, and Swift SDKs

This document compares the ergonomic high-level APIs available in the MCP SDKs.

## Summary

| SDK | High-Level API | Low-Level API |
|-----|---------------|---------------|
| Python | `FastMCP` | `mcp.server.lowlevel.Server` |
| TypeScript | `McpServer` | `Server` |
| Swift | None (planned) | `Server` |

The Swift SDK currently only provides a low-level API and lacks a high-level ergonomic wrapper like FastMCP (Python) or McpServer (TypeScript). However, the low-level API is well-designed to support adding high-level convenience APIs in a future PR.

## Python: FastMCP

FastMCP provides a Flask/FastAPI-style decorator API that significantly reduces boilerplate.

### Example

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Echo Server")

@mcp.tool()
def echo(text: str) -> str:
    """Echo the input text"""
    return text

@mcp.resource("config://app")
def get_config() -> str:
    return "{ \"debug\": true }"

@mcp.prompt()
def greeting(name: str) -> str:
    return f"Hello, {name}!"

# Run with built-in transport setup
mcp.run(transport="stdio")
```

### Key Features

- **Decorator-based registration**: `@mcp.tool()`, `@mcp.resource()`, `@mcp.prompt()`
- **Auto-generated schemas**: Input schemas derived from Python type hints (supports Pydantic, TypedDict, dataclasses)
- **Automatic routing**: Each decorated function is a separate tool/resource/prompt
- **Built-in transport**: `mcp.run(transport="stdio|sse|streamable-http")`
- **Context injection**: Automatic `Context` parameter injection for logging, progress, etc.
- **Settings via environment**: `pydantic-settings` with `FASTMCP_*` env vars
- **Managers**: Internal `ToolManager`, `ResourceManager`, `PromptManager` handle registration
- **Custom HTTP routes**: `@mcp.custom_route("/health", "GET")` for non-MCP endpoints

### Context Capabilities

Tools can request a `Context` parameter for accessing server capabilities:

```python
@mcp.tool()
async def long_task(ctx: Context, text: str) -> str:
    ctx.info(f"Processing: {text}")
    ctx.report_progress(progress=0, total=100)
    # ... work ...
    ctx.report_progress(progress=100, total=100)
    return "Done"
```

| Method | Description |
|--------|-------------|
| `ctx.info()`, `ctx.debug()`, `ctx.warning()`, `ctx.error()` | Logging at different levels |
| `ctx.report_progress(progress, total)` | Progress reporting |
| `ctx.read_resource(uri)` | Read a resource from within a tool |
| `ctx.elicit(...)` | Request user input |
| `ctx.request_id` | Access the request ID |

### Architecture

FastMCP wraps the low-level server internally:

```python
class FastMCP:
    def __init__(self, ...):
        self._mcp_server = MCPServer(...)  # Low-level server
        self._tool_manager = ToolManager(...)
        self._resource_manager = ResourceManager(...)
        self._prompt_manager = PromptManager(...)
```

## TypeScript: McpServer

McpServer provides a similar high-level API using method-based registration with Zod schemas.

### Example

```typescript
import { McpServer, StdioServerTransport } from '@modelcontextprotocol/server';
import * as z from 'zod/v4';

const server = new McpServer({
    name: 'weather-server',
    version: '1.0.0'
});

server.registerTool(
    'get_weather',
    {
        description: 'Get weather information for a city',
        inputSchema: {
            city: z.string().describe('City name'),
            country: z.string().describe('Country code')
        },
        outputSchema: {
            temperature: z.number(),
            conditions: z.enum(['sunny', 'cloudy', 'rainy'])
        }
    },
    async ({ city, country }) => {
        return {
            content: [{ type: 'text', text: `Weather for ${city}` }],
            structuredContent: { temperature: 22, conditions: 'sunny' }
        };
    }
);

const transport = new StdioServerTransport();
await server.connect(transport);
```

### Key Features

- **Method-based registration**: `registerTool()`, `registerPrompt()`, `registerResource()`
- **Zod schema validation**: Input/output schemas using Zod
- **Automatic routing**: Each registered item dispatched by name
- **Exposes low-level server**: `server.server` for advanced operations
- **Dynamic updates**: `RegisteredTool` has `.update()` and `.remove()` methods
- **List change notifications**: `sendToolListChanged()`, `sendResourceListChanged()`, `sendPromptListChanged()`
- **Experimental tasks**: `server.experimental.tasks` for long-running operations

### Architecture

McpServer wraps the low-level Server:

```typescript
class McpServer {
    public readonly server: Server;  // Low-level server exposed
    private _registeredTools: { [name: string]: RegisteredTool } = {};
    private _registeredPrompts: { [name: string]: RegisteredPrompt } = {};
    private _registeredResources: { [uri: string]: RegisteredResource } = {};
}
```

## Swift: Low-Level API

The Swift SDK provides a low-level API with manual handler setup. It follows the same per-client Server architecture as TypeScript.

### Example

```swift
let server = Server(
    name: "test-server",
    version: "1.0.0",
    capabilities: .init(tools: .init())
)

// Register tool list handler
server.withRequestHandler(ListTools.self) { _, _ in
    ListTools.Result(tools: [
        Tool(
            name: "greet",
            description: "A simple greeting tool",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Name to greet"]
                ]
            ]
        )
    ])
}

// Register tool call handler - manual dispatch required
server.withRequestHandler(CallTool.self) { request, context in
    switch request.name {
    case "greet":
        let name = request.arguments?["name"]?.stringValue ?? "World"
        return CallTool.Result(content: [.text("Hello, \(name)!")])
    default:
        throw MCPError.invalidParams("Unknown tool: \(request.name)")
    }
}

try await server.start(transport: transport)
```

### Current State

The Swift SDK is **low-level only** but has strong foundations:

**What's implemented:**
- `withRequestHandler()` for type-safe handler registration
- `RequestHandlerContext` with progress, logging, elicitation, cancellation
- Client convenience methods: `callTool()`, `listTools()`, `readResource()`, etc.
- List change notifications: `sendToolListChanged()`, `sendResourceListChanged()`, `sendPromptListChanged()`
- Experimental tasks support

**What's missing (planned for future PR):**
- High-level wrapper class (like `McpServer` or `FastMCP`)
- Automatic tool/resource/prompt registration
- Automatic JSON Schema generation from Swift types
- Automatic routing/dispatch

## Feature Comparison

### Server Registration APIs

| Feature | Python FastMCP | TypeScript McpServer | Swift SDK |
|---------|---------------|---------------------|-----------|
| High-level API | `FastMCP` class | `McpServer` class | None (planned) |
| Tool registration | `@mcp.tool()` decorator | `registerTool()` method | `withRequestHandler()` |
| Schema generation | Auto from type hints | Auto from Zod schemas | Manual JSON Schema |
| Tool routing | Automatic | Automatic | Manual switch |
| Resource registration | `@mcp.resource()` | `registerResource()` | `withRequestHandler()` |
| Prompt registration | `@mcp.prompt()` | `registerPrompt()` | `withRequestHandler()` |
| Transport setup | `mcp.run()` | `server.connect()` | `server.start()` |
| Dynamic add/remove | `add_tool()`, `remove_tool()` | `.update()`, `.remove()` | Manual |
| List change notifications | Automatic | `sendToolListChanged()` | `sendToolListChanged()` |
| Custom HTTP routes | `@mcp.custom_route()` | N/A | N/A |

### Context/Handler Capabilities

| Capability | Python (Context) | TypeScript (extra) | Swift (RequestHandlerContext) |
|------------|-----------------|-------------------|------------------------------|
| Progress reporting | `ctx.report_progress()` | `extra.reportProgress()` | `sendProgress()` |
| Logging | `ctx.info()`, `ctx.debug()`, etc. | `extra.log()` | `sendLogMessage()` |
| Read resources | `ctx.read_resource(uri)` | N/A | N/A |
| Elicitation | `ctx.elicit(...)` | `extra.elicit()` | `elicit()`, `elicitUrl()` |
| Request ID | `ctx.request_id` | `extra.requestId` | `requestId` |
| Cancellation | asyncio-based | `extra.signal` (AbortSignal) | `isCancelled`, `checkCancellation()` |

### Client Convenience Methods

| Method | Python | TypeScript | Swift |
|--------|--------|------------|-------|
| List tools | `session.list_tools()` | `client.listTools()` | `client.listTools()` |
| Call tool | `session.call_tool()` | `client.callTool()` | `client.callTool()` |
| List resources | `session.list_resources()` | `client.listResources()` | `client.listResources()` |
| Read resource | `session.read_resource()` | `client.readResource()` | `client.readResource()` |
| List prompts | `session.list_prompts()` | `client.listPrompts()` | `client.listPrompts()` |
| Get prompt | `session.get_prompt()` | `client.getPrompt()` | `client.getPrompt()` |
| Subscribe to resource | `session.subscribe_resource()` | `client.subscribeResource()` | `client.subscribeToResource()` |

## The Routing Problem

### What is Routing?

Routing refers to dispatching incoming MCP requests (`CallTool`, `GetPrompt`, `ReadResource`) to the correct handler based on the tool name, prompt name, or resource URI. This is the core functionality that high-level APIs provide.

### Current Swift Approach: Manual Dispatch

The Swift SDK requires developers to write manual switch statements:

```swift
server.withRequestHandler(CallTool.self) { request, context in
    switch request.name {
    case "get_weather":
        // Handle get_weather tool
    case "send_email":
        // Handle send_email tool
    default:
        throw MCPError.invalidParams("Unknown tool: \(request.name)")
    }
}

server.withRequestHandler(GetPrompt.self) { request, context in
    switch request.name {
    case "greeting":
        // Handle greeting prompt
    default:
        throw MCPError.invalidParams("Unknown prompt: \(request.name)")
    }
}
```

**Problems with manual routing:**
1. Boilerplate grows linearly with number of tools/resources/prompts
2. Tool definitions (`ListTools`) are separate from implementations (`CallTool`)
3. Easy to forget adding a tool to the switch or the list
4. No compile-time verification that all tools are handled

### Solution: Registry-Based Automatic Routing

Both Python and TypeScript solve this with registries that store handlers keyed by name:

```typescript
// TypeScript McpServer internals
private _registeredTools: { [name: string]: RegisteredTool } = {};

registerTool(name, schema, handler) {
    this._registeredTools[name] = { schema, handler };
}

// Internal CallTool handler
this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const tool = this._registeredTools[request.params.name];
    if (!tool) throw new McpError(...);
    return tool.handler(request.params.arguments);
});
```

### Proposed Swift Implementation

A `ToolRegistry` actor would provide automatic routing:

```swift
public actor ToolRegistry {
    private var tools: [String: RegisteredTool] = [:]

    public func register<Input: Codable, Output: Codable>(
        name: String,
        description: String,
        inputType: Input.Type,
        outputType: Output.Type,
        handler: @escaping @Sendable (Input, ToolContext) async throws -> Output
    ) {
        let schema = JSONSchemaGenerator.generate(from: inputType)
        tools[name] = RegisteredTool(
            definition: Tool(name: name, description: description, inputSchema: schema),
            handler: { args, context in
                let input = try JSONDecoder().decode(Input.self, from: args)
                let output = try await handler(input, context)
                return try JSONEncoder().encode(output)
            }
        )
    }

    internal func listTools() -> [Tool] {
        tools.values.map(\.definition)
    }

    internal func callTool(name: String, arguments: Value?, context: ToolContext) async throws -> CallTool.Result {
        guard let tool = tools[name] else {
            throw MCPError.invalidParams("Unknown tool: \(name)")
        }
        return try await tool.handler(arguments, context)
    }
}
```

The high-level `MCPServer` wrapper would use this registry internally:

```swift
public actor MCPServer {
    public let server: Server
    private let toolRegistry = ToolRegistry()
    private let promptRegistry = PromptRegistry()
    private let resourceRegistry = ResourceRegistry()

    public init(name: String, version: String) {
        self.server = Server(name: name, version: version, capabilities: .init(tools: .init()))

        // Wire up automatic routing
        server.withRequestHandler(ListTools.self) { [toolRegistry] _, _ in
            ListTools.Result(tools: await toolRegistry.listTools())
        }

        server.withRequestHandler(CallTool.self) { [toolRegistry] request, context in
            try await toolRegistry.callTool(
                name: request.name,
                arguments: request.arguments,
                context: ToolContext(from: context)
            )
        }

        // Similar for prompts and resources...
    }

    public func registerTool<Input: Codable, Output: Codable>(
        name: String,
        description: String,
        inputType: Input.Type,
        outputType: Output.Type,
        handler: @escaping @Sendable (Input, ToolContext) async throws -> Output
    ) async {
        await toolRegistry.register(
            name: name,
            description: description,
            inputType: inputType,
            outputType: outputType,
            handler: handler
        )
    }
}
```

### Usage After Implementation

```swift
let server = MCPServer(name: "weather-server", version: "1.0.0")

// Registration is separate from routing - no switch statement needed
await server.registerTool(
    name: "get_weather",
    description: "Get weather for a city",
    inputType: WeatherInput.self,
    outputType: WeatherOutput.self
) { input, context in
    WeatherOutput(temperature: 22, conditions: .sunny)
}

await server.registerTool(
    name: "send_email",
    description: "Send an email",
    inputType: EmailInput.self,
    outputType: EmailResult.self
) { input, context in
    // Send email...
    EmailResult(sent: true)
}

// Routing happens automatically - MCPServer dispatches to the right handler
try await server.start(transport: transport)
```

### Benefits of Registry-Based Routing

1. **Single source of truth** - Tool definition and implementation are registered together
2. **No manual dispatch** - Registry handles name-based lookup
3. **Type-safe** - Input/output types are verified at registration
4. **Dynamic updates** - Tools can be added/removed at runtime
5. **Automatic list generation** - `ListTools` reads from the registry

### Full Implementation

See `mcp-tool-dsl-design.md` for the complete implementation plan, including:
- `ToolRegistry` actor with validation integration
- Server `withValidatedToolHandler` method
- DSL macros (`@Tool`, `@Parameter`) for declarative tool definition
- JSON Schema validation flow

## Potential Swift High-Level API Design

A hypothetical Swift high-level API could leverage:

### Option 1: Swift Macros (Swift 5.9+)

```swift
@Tool
struct GetWeather {
    static let name = "get_weather"
    static let description = "Get weather for a city"

    @Parameter(description: "City name")
    var city: String

    @Parameter(description: "Country code")
    var country: String

    func perform(context: ToolContext) async throws -> String {
        "Weather for \(city), \(country): 22°C, sunny"
    }
}
```

See `mcp-tool-dsl-design.md` for the detailed design document.

### Option 2: Builder Pattern

```swift
let server = MCPServer("weather-server", version: "1.0.0")
    .tool("get_weather", description: "Get weather") { (city: String, country: String) in
        Weather(temperature: 22, conditions: .sunny)
    }
    .resource("config://app") {
        "{ \"debug\": true }"
    }
    .prompt("greeting") { (name: String) in
        "Hello, \(name)!"
    }
```

### Option 3: Registration Methods (like TypeScript)

```swift
let server = MCPServer(name: "weather-server", version: "1.0.0")

server.registerTool(
    name: "get_weather",
    description: "Get weather for a city",
    inputType: WeatherInput.self,  // Codable type
    outputType: Weather.self
) { input in
    Weather(temperature: 22, conditions: .sunny)
}
```

### Implementation Considerations

1. **Schema Generation**: Use `Codable` and macros to generate JSON Schema from Swift types
2. **Type Safety**: Leverage Swift's strong typing for input/output validation
3. **Async Support**: Native `async/await` integration
4. **Actor Isolation**: Consider `@MainActor` or custom actor for state management
5. **SwiftUI Integration**: Potential for `@Observable` server state

## Architecture Assessment: Swift SDK Readiness

The Swift SDK's low-level architecture is **well-designed to accommodate high-level APIs** without requiring changes to the current implementation:

### Why No Changes Are Needed Now

1. **Handler registration** - `withRequestHandler()` returns `Self` for chaining; high-level APIs can wrap this internally

2. **RequestHandlerContext** - Already provides progress, logging, elicitation, cancellation - can be wrapped in a simpler `ToolContext` for DSL tools

3. **Actor-based Server** - Safe for storing tool/resource/prompt registries with proper isolation

4. **Transport abstraction** - Well-designed for adding a `run(transport:)` convenience method

5. **Composition pattern** - High-level APIs (like `McpServer` in TypeScript) are wrappers that expose a public `server` property. They don't modify the low-level server—they compose it.

### Extension Points

| Extension Point | Current State | How High-Level API Would Use It |
|----------------|---------------|--------------------------------|
| `withRequestHandler()` | Works, chainable | Called internally by `registerTool()` |
| `RequestHandlerContext` | Rich API | Wrapped in `ToolContext` |
| `Server` actor | Thread-safe | Stores tool/resource/prompt registries |
| Transport abstraction | Complete | Used by `run(transport:)` method |
| List change notifications | Implemented | Called when tools/resources/prompts change |

### Prerequisites for High-Level API

The main prerequisites for implementing the macro-based DSL (Option 1) are:

1. **JSON Schema Validator** - Needed for input/output validation (see `schema-validation/` docs)
2. **SwiftSyntax Dependency** - Required for `@Tool` and `@Parameter` macros
3. **ToolRegistry** - New type to store and execute DSL-based tools

These can all be added in a future PR without modifying the existing low-level API.

## Conclusion

The Swift SDK would benefit from a high-level API similar to FastMCP or McpServer. The macro-based approach (Option 1) would provide the most ergonomic API while leveraging Swift's modern features, though the registration method approach (Option 3) would be simpler to implement initially.

**The current low-level architecture is ready** - no changes are needed in the current PR to support future high-level convenience APIs. The design follows the same composition pattern as TypeScript's `McpServer`, which wraps rather than modifies the low-level `Server`.

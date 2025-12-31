# Documentation Inventory

This document compares the current README documentation against the expanded codebase to identify gaps and updates needed.

## Summary

| Category | Documented | Undocumented | Needs Update |
|----------|------------|--------------|--------------|
| Transports | 4 | 2 | 1 |
| Client Features | 8 | 6 | 2 |
| Server Features | 9 | 8 | 3 |
| Protocol Types | 3 | 6 | 1 |
| Experimental | 0 | 1 (Tasks) | - |
| Examples | 0 | 2 | - |

## Current README Coverage

### Fully Documented
- Overview, Requirements, Installation
- Client: Basic setup, connect, capabilities checking
- Client: Stdio and HTTP transports
- Client: Tools (list, call)
- Client: Resources (list, read, subscribe)
- Client: Prompts (list, get)
- Client: Sampling handler
- Client: Error handling
- Client: Strict vs non-strict configuration
- Client: Request batching
- Server: Basic setup, start, capabilities
- Server: Tools (ListTools, CallTool handlers)
- Server: Progress notifications via RequestHandlerContext
- Server: Resources (ListResources, ReadResource, Subscribe handlers)
- Server: Prompts (ListPrompts, GetPrompt handlers)
- Server: Sampling (requestSampling)
- Server: Initialize hook
- Server: Graceful shutdown with ServiceLifecycle
- Transports: StdioTransport, HTTPClientTransport, InMemoryTransport, NetworkTransport
- Custom Transport Implementation
- Platform Availability
- Debugging and Logging

## Undocumented Features (New)

### Transports

#### HTTPServerTransport
**File:** `Sources/MCP/Base/Transports/HTTPServerTransport.swift` (45KB)

Full HTTP server transport for hosting MCP servers. Features:
- Stateful and stateless modes
- Session ID management
- SSE streaming support
- Request/response multiplexing
- Integration with any HTTP framework (Hummingbird, Vapor, etc.)

```swift
let transport = HTTPServerTransport(
    options: .init(
        sessionIdGenerator: { UUID().uuidString },
        onSessionInitialized: { sessionId in ... },
        onSessionClosed: { sessionId in ... }
    )
)
```

#### OAuth Support
**File:** `Sources/MCP/Base/Transports/OAuth.swift`

OAuth 2.0 types for authenticated HTTP transports:
- `OAuthTokens` - Access/refresh tokens per RFC 6749
- `UnauthorizedContext` - 401 response handling
- `OAuthClientProvider` - Protocol for OAuth providers (not yet implemented)

### Client Features

#### Elicitation
**File:** `Sources/MCP/Client/Elicitation.swift` (26KB)

Allows servers to request additional information from users through the client:
- `StringSchema`, `NumberSchema`, `BooleanSchema`, `EnumSchema`
- `ElicitationSchema` - Form definitions with multiple fields
- `withElicitationHandler` - Register handler for elicitation requests

```swift
await client.withElicitationHandler { request in
    // Show form to user, return their responses
    return ElicitResult(action: .accept, content: [...])
}
```

#### Roots
**File:** `Sources/MCP/Client/Roots.swift`

Filesystem roots that clients expose to servers:
- `Root` - Represents a `file://` URI root
- `withRootsHandler` - Register handler for roots/list requests
- `sendRootsChanged()` - Notify server when roots change

```swift
await client.withRootsHandler {
    return [Root(uri: "file:///Users/me/projects", name: "Projects")]
}
```

#### Request Cancellation
**File:** `Sources/MCP/Client/Client+Requests.swift`

Cancel in-flight requests:
```swift
await client.cancelRequest(requestId, reason: "User cancelled")
```

#### Completion (Autocomplete)
**File:** `Sources/MCP/Server/Completions.swift`

Autocomplete for prompt arguments and resource template URIs:
```swift
let result = try await client.complete(
    ref: .prompt(PromptReference(name: "greet")),
    argument: .init(name: "name", value: "Jo")
)
// result.completion.values = ["John", "Joan", "Joseph"]
```

#### Request Timeout Configuration
**File:** `Sources/MCP/Client/Client+Requests.swift`

Configure timeouts per-request:
```swift
try await client.send(request, timeout: .seconds(30))
```

### Server Features

#### Elicitation (Server → Client)
**File:** `Sources/MCP/Server/Server.swift`

Server requesting user input from client:
```swift
let result = try await context.elicit(
    message: "Please provide your API key",
    schema: ElicitationSchema(properties: [
        "apiKey": .string(StringSchema(title: "API Key", format: .password))
    ])
)
```

#### URL Elicitation
**File:** `Sources/MCP/Server/Server.swift`

Server requesting user to visit a URL (e.g., for OAuth):
```swift
try await context.elicitUrl(
    url: "https://example.com/authorize",
    reason: "Please authorize this application"
)
```

#### Completions Handler
**File:** `Sources/MCP/Server/Completions.swift`

Register autocomplete handlers:
```swift
await server.withRequestHandler(Complete.self) { params in
    // Return completion suggestions
}
```

#### SessionManager
**File:** `Sources/MCP/Server/SessionManager.swift`

Thread-safe session storage for HTTP servers:
```swift
let sessionManager = SessionManager(maxSessions: 100)
await sessionManager.store(transport, forSessionId: sessionId)
await sessionManager.cleanupStaleSessions(olderThan: .seconds(3600))
```

#### Tool Annotations
**File:** `Sources/MCP/Server/Tools.swift`

Rich metadata for tools:
```swift
Tool(
    name: "delete_file",
    annotations: .init(
        title: "Delete File",
        destructiveHint: true,
        idempotentHint: false,
        readOnlyHint: false
    )
)
```

#### Tool Execution Settings
**File:** `Sources/MCP/Server/Tools.swift`

Task support configuration:
```swift
Tool(
    name: "long_running",
    execution: .init(taskSupport: .supported)
)
```

#### Icons
**File:** `Sources/MCP/Base/Icon.swift`

Icon support for clients, servers, tools, and resources:
```swift
let icon = Icon(uri: "https://example.com/icon.png", mimeType: "image/png")
```

#### Server → Client Requests
**File:** `Sources/MCP/Server/Server+ClientRequests.swift`

Server can send requests to client:
```swift
let result = try await server.sendRequest(ListRoots.request())
```

### Protocol Types

#### Protocol Versioning
**File:** `Sources/MCP/Base/Versioning.swift`

Version constants and negotiation:
- `Version.v2025_11_25` - Tasks, icons, URL elicitation
- `Version.v2025_06_18` - Elicitation, structured output
- `Version.v2025_03_26` - JSON-RPC batching
- `Version.v2024_11_05` - Initial stable release
- `Version.supported` - All supported versions
- `Version.latest` - Current latest version

#### Annotations
**File:** `Sources/MCP/Base/Annotations.swift`

Content annotations:
```swift
Annotations(
    audience: [.user, .assistant],
    priority: 0.8,
    lastModified: "2024-01-15T10:30:00Z"
)
```

#### Resource Templates
**File:** `Sources/MCP/Server/Resources.swift`

URI templates for dynamic resources:
```swift
Resource.Template(
    uriTemplate: "file:///{path}",
    name: "File",
    description: "Access files by path"
)
```

#### Title Fields
Multiple files

New `title` field on many types for UI display:
- `Client.Info.title`
- `Server.Info.title`
- `Tool.annotations.title`
- `Prompt.title`
- `Resource.title`

#### Error Codes
**File:** `Sources/MCP/Base/Error.swift`

Comprehensive error types:
- Standard JSON-RPC errors
- MCP-specific: `resourceNotFound`, `urlElicitationRequired`
- SDK-specific: `connectionClosed`, `requestTimeout`, `transportError`, `requestCancelled`

### Experimental Features

#### Tasks
**Files:** `Sources/MCP/Server/Experimental/Tasks/*.swift` (~127KB total)

Full task tracking for long-running operations:

**Types:**
- `TaskStatus` - working, inputRequired, completed, failed, cancelled
- `MCPTask` - Full task representation with metadata
- `TaskStore` - In-memory task storage
- `TaskMessageQueue` - Message queueing for tasks
- `TaskContext` / `ServerTaskContext` - Context for task operations

**Server API:**
```swift
// Enable task support
await server.experimental.tasks.enable()

// Task-augmented tool calls
await context.sendTaskStatus(task)
```

**Client API:**
```swift
// Task polling
let task = try await client.experimental.tasks.get(taskId)
let tasks = try await client.experimental.tasks.list()
try await client.experimental.tasks.cancel(taskId)
```

### Examples

#### HummingbirdIntegration
**Location:** `Examples/HummingbirdIntegration/`

Complete HTTP server example using Hummingbird framework.

#### VaporIntegration
**Location:** `Examples/VaporIntegration/`

Complete HTTP server example using Vapor framework.

Both examples documented in `Examples/README.md` but not referenced from main README.

## Documentation Needs Update

### HTTPClientTransport
Current documentation shows basic usage. Needs update for:
- Session ID handling
- Protocol version header
- Streaming mode options

### Progress Notifications
Currently documented for server. Missing:
- Client-side progress notification handling
- Progress token in request metadata

### Sampling
Currently shows basic flow. Missing:
- `includeContext` parameter
- Tools in sampling requests
- Model preferences

## Recommended Documentation Structure

Based on this inventory, the DocC articles should cover:

### GettingStarted.md
- Quick client example
- Quick server example
- Link to full guides

### ClientGuide.md
- Basic setup and connection
- Transport options (Stdio, HTTP)
- Tools, Resources, Prompts
- Sampling handler
- **NEW:** Elicitation handler
- **NEW:** Roots handler
- **NEW:** Request timeouts and cancellation
- **NEW:** Completion (autocomplete)
- Batching
- Error handling

### ServerGuide.md
- Basic setup and capabilities
- Request handlers
- Tools, Resources, Prompts
- Progress notifications
- **NEW:** Elicitation (server → client)
- **NEW:** URL Elicitation
- **NEW:** Completions handler
- **NEW:** Tool annotations
- **NEW:** Icons
- Sampling requests
- Initialize hook
- Graceful shutdown

### Transports.md
- Overview of transport options
- StdioTransport
- HTTPClientTransport (updated)
- **NEW:** HTTPServerTransport
- InMemoryTransport
- NetworkTransport
- Custom transport implementation
- **NEW:** SessionManager
- **NEW:** OAuth types

### Experimental.md (new)
- **NEW:** Tasks overview
- **NEW:** Enabling task support
- **NEW:** Task lifecycle
- **NEW:** Task-augmented tool calls
- **NEW:** Client task polling

### Debugging.md
- Logging configuration
- Error handling
- **NEW:** Error codes reference

# Swift MCP SDK Architecture Analysis and Refactoring Recommendations

## Executive Summary

The Swift MCP SDK has a well-designed transport layer but lacks an intermediate **Session/Protocol layer** that both the TypeScript and Python reference SDKs implement. This missing layer causes several architectural issues:

1. **Leaked HTTP-specific abstractions** in the `Transport` protocol
2. **Mixed responsibilities** in `Client` and `Server` actors
3. **Tight coupling** to specific transport implementations
4. **Redundant code** between Client and Server for message routing

The recommended refactoring introduces a **Protocol layer** (similar to TypeScript) that handles JSON-RPC mechanics, while keeping the current `Client` and `Server` actors as MCP-specific facades.

---

## Current Architecture Comparison

### TypeScript SDK Structure
```
Transport (minimal: send, start, close, onmessage)
    ↓
Protocol (JSON-RPC framing, request/response correlation, handlers)
    ↓
Client/Server (MCP-specific logic, capabilities, convenience methods)
```

### Python SDK Structure
```
Transport → (read_stream, write_stream) tuple
    ↓
BaseSession (message pump, request/response correlation)
    ↓
ClientSession/ServerSession (MCP protocol logic + public API)
```

**Note:** Unlike what might be expected, Python does not have a separate "Client" facade class. `ClientSession` IS the client API that users work with directly. This is a simpler layering than TypeScript.

### Current Swift SDK Structure
```
Transport (includes HTTP context, session ID, SSE closures)
    ↓
Client/Server (everything: JSON-RPC, MCP logic, message routing)
```

---

## Detailed Problem Analysis

### Problem 1: Leaked Abstractions in Transport Protocol

**File:** `Sources/MCP/Base/Transport.swift`

The `Transport` protocol contains HTTP-specific fields that don't belong in a transport abstraction:

```swift
public protocol Transport: Actor {
    // HTTP-specific: session management
    var sessionId: String? { get }

    // HTTP-specific: bidirectional support detection
    var supportsServerToClientRequests: Bool { get }

    // HTTP-specific: request ID for response multiplexing
    func send(_ data: Data, relatedRequestId: RequestId?) async throws
}

public struct MessageContext: Sendable {
    // HTTP-specific: OAuth/token auth
    public let authInfo: AuthInfo?

    // HTTP-specific: request headers
    public let requestInfo: RequestInfo?

    // HTTP-specific: SSE stream management
    public let closeSSEStream: (@Sendable () async -> Void)?
    public let closeStandaloneSSEStream: (@Sendable () async -> Void)?
}
```

**Comparison with TypeScript:**
```typescript
// TypeScript Transport is minimal - no HTTP fields
interface Transport {
    start(): Promise<void>;
    send(message: JSONRPCMessage, options?: TransportSendOptions): Promise<void>;
    close(): Promise<void>;
    onclose?: () => void;                    // Connection closed callback
    onerror?: (error: Error) => void;        // Error callback
    onmessage?: <T extends JSONRPCMessage>(message: T, extra?: MessageExtraInfo) => void;
    sessionId?: string;                      // Optional, only HTTP uses it
    setProtocolVersion?: (version: string) => void;  // Optional, for HTTP
}

// HTTP-specific context flows through optional MessageExtraInfo
interface MessageExtraInfo {
    authInfo?: AuthInfo;
    requestInfo?: RequestInfo;
    closeSSEStream?: () => void;
}
```

**Note:** Swift's use of `AsyncThrowingStream` for `receive()` is actually more idiomatic than TypeScript's callbacks. The stream naturally handles `onclose` (stream termination), `onerror` (throwing), and `onmessage` (yielding values). This is a strength of the current Swift design that should be preserved.

### Problem 2: Mixed Responsibilities in Client/Server

**Files:**
- `Sources/MCP/Client/Client.swift` (1041 lines)
- `Sources/MCP/Server/Server.swift` (1304 lines)

Both `Client` and `Server` handle:
- Connection management
- Request/response correlation (`pendingRequests`, `AnyPendingRequest`)
- Handler registration
- Notification routing
- Progress callback management
- Timeout handling
- Message encoding/decoding
- MCP-specific protocol logic

**TypeScript separates these:**
```typescript
// Protocol handles JSON-RPC mechanics
class Protocol {
    private _requestHandlers: Map<string, Handler>;
    private _responseHandlers: Map<number, (response) => void>;
    private _progressHandlers: Map<number, ProgressCallback>;
    private _timeoutInfo: Map<number, TimeoutInfo>;

    request<T>(request, schema, options): Promise<T>;
    notification(notification, options): Promise<void>;
    setRequestHandler(schema, handler): void;
}

// Client/Server extend Protocol with MCP-specific logic
class Client extends Protocol {
    // Only MCP-specific: capabilities, initialization, convenience methods
    async listTools(): Promise<ListToolsResult>;
    async callTool(params): Promise<CallToolResult>;
}
```

### Problem 3: Direct Transport Type Casting

**File:** `Sources/MCP/Client/Client.swift` (lines 1027-1030)

```swift
// HTTP transports must set the protocol version in headers after initialization
if let httpTransport = connection as? HTTPClientTransport {
    await httpTransport.setProtocolVersion(result.protocolVersion)
}
```

This violates the abstraction - the Client shouldn't need to know about `HTTPClientTransport`.

**TypeScript solution:** The `Transport` interface includes an optional `setProtocolVersion` method:
```typescript
interface Transport {
    setProtocolVersion?: (version: string) => void;
}
```

---

## Gaps and Missing Considerations

This section documents gaps identified during architectural review that must be addressed in the implementation.

### Gap 1: ResponseRouter Pattern Integration

The Swift SDK already has a `ResponseRouter` protocol used for task result handling (visible in Server.swift: `var responseRouters: [any ResponseRouter] = []`). The Protocol layer must either:
- Absorb this functionality internally, OR
- Provide hooks for router registration

**Recommendation:** The Protocol layer should expose a `ResponseRouter` registration mechanism so Server can continue to use this pattern for task-related response routing.

### Gap 2: Batch Request Handling

The Swift SDK supports batch requests (`Server.Batch` type). The plan doesn't address how the Protocol layer will handle batch request/response correlation. TypeScript's Protocol class does not explicitly handle batching either; this appears to be transport-level.

**Recommendation:** Explicitly state that batch handling remains at the transport level. The Protocol layer should process individual messages from the batch after transport-level unpacking.

### Gap 3: Progress Token to Task ID Mapping

Both TypeScript and Swift SDKs maintain mappings from progress tokens to task IDs to keep progress handlers alive after `CreateTaskResult` is returned:

```typescript
// TypeScript (protocol.ts)
private _taskProgressTokens: Map<string, number> = new Map();
```

```swift
// Swift (Client.swift)
var taskProgressTokens: [String: ProgressToken] = [:]
```

**Recommendation:** Add this state to the `MCPProtocol` actor design:
```swift
private var taskProgressTokens: [String: ProgressToken] = [:]
```

### Gap 4: Notification Debouncing

TypeScript's Protocol class supports notification debouncing for high-frequency notifications:
```typescript
private debouncedNotificationMethods: Set<string>
```

This allows notifications like `resources/list_changed` to be debounced to avoid flooding the transport.

**Recommendation:** Include notification debouncing infrastructure in the Protocol layer design, even if not immediately used. This is a forward-compatible addition.

### Gap 5: Handler Task Management

The proposed handler invocation pattern creates unstructured tasks:
```swift
Task {
    let result = try await handler(params, context)
    await self.sendResponse(result, for: requestId)
}
```

These tasks could outlive the Protocol actor, causing issues during shutdown.

**Recommendation:** Use a `TaskGroup` owned by the Protocol actor, or maintain a `Set<Task<Void, Never>>` for tracking in-flight handler tasks (as the current Swift SDK already does with `inFlightHandlerTasks`). This enables:
- Graceful cancellation of handlers during disconnect
- Tracking of active operations
- Proper cleanup on actor deinit

### Gap 6: Tool Output Schema Caching

Client implementations cache tool output schemas for validation. This is client-specific behavior.

**Recommendation:** Clarify in the architecture that tool schema caching remains in Client, not Protocol. The Protocol layer is transport-agnostic and doesn't understand MCP semantics like tools.

---

## Proposed Architecture

### New Type Hierarchy

```
Sources/MCP/
├── Base/
│   ├── Transport.swift (simplified - minimal interface)
│   ├── TransportMessage.swift (new - extracted types)
│   ├── Protocol.swift (new - JSON-RPC mechanics)
│   ├── RequestHandlerExtra.swift (new - handler context)
│   └── Transports/
│       ├── StdioTransport.swift (unchanged)
│       ├── HTTPServerTransport.swift (minor changes)
│       └── HTTPClientTransport.swift (minor changes)
├── Client/
│   └── Client.swift (slimmed - MCP logic only)
└── Server/
    └── Server.swift (slimmed - MCP logic only)
```

### New Protocol Layer Design

```swift
// Sources/MCP/Base/Protocol.swift

/// Base protocol implementation for JSON-RPC message handling.
/// Handles request/response correlation, handlers, progress, and timeouts.
///
/// This is the Swift equivalent of TypeScript's Protocol class and
/// Python's BaseSession.
///
/// Note on type parameters: TypeScript's Protocol has 3 type parameters
/// (SendRequestT, SendNotificationT, SendResultT). This design uses 5 to
/// also constrain received types. Evaluate during implementation whether
/// this added type safety is worth the complexity.
public actor MCPProtocol<
    SendRequest,
    SendNotification,
    SendResult,
    ReceiveRequest,
    ReceiveNotification
> {
    // Connection state
    private var transport: (any Transport)?

    // Request/response tracking
    private var requestMessageId = 0
    private var pendingRequests: [RequestId: AnyPendingRequest] = [:]
    private var progressCallbacks: [ProgressToken: ProgressCallback] = [:]
    private var timeoutControllers: [ProgressToken: TimeoutController] = [:]

    // Task support (keeps progress handlers alive after CreateTaskResult)
    private var taskProgressTokens: [String: ProgressToken] = [:]

    // Handler registrations
    private var requestHandlers: [String: RequestHandlerBox] = [:]
    private var notificationHandlers: [String: [NotificationHandlerBox]] = [:]

    // In-flight handler tasks for graceful shutdown
    private var inFlightHandlerTasks: Set<Task<Void, Never>> = []

    // Callbacks
    public var onClose: (() async -> Void)?
    public var onError: ((Error) async -> Void)?

    /// Connect to a transport and start processing messages.
    public func connect(transport: any Transport) async throws {
        self.transport = transport
        try await transport.connect()
        startMessageLoop()
    }

    /// Send a request and wait for response.
    public func request<R: Decodable>(
        _ request: some RequestMessageProtocol,
        options: RequestOptions? = nil
    ) async throws -> R {
        // Implementation: encode, track, send, wait for response
    }

    /// Send a notification (fire-and-forget).
    public func notification(
        _ notification: some NotificationMessageProtocol,
        options: NotificationOptions? = nil
    ) async throws {
        // Implementation: encode, send
    }

    /// Register a request handler.
    public func setRequestHandler<M: Method>(
        _ type: M.Type,
        handler: @escaping (M.Parameters, RequestHandlerExtra) async throws -> M.Result
    ) {
        // Implementation: store handler
    }

    /// Register a notification handler.
    public func setNotificationHandler<N: Notification>(
        _ type: N.Type,
        handler: @escaping (Message<N>) async throws -> Void
    ) {
        // Implementation: store handler
    }
}
```

### Simplified Transport Protocol

The Transport protocol should use optional methods with default implementations rather than a separate `HTTPTransport` protocol. This matches TypeScript's approach where `sessionId` and `setProtocolVersion` are optional on the base `Transport` interface.

```swift
// Sources/MCP/Base/Transport.swift (simplified)

/// Minimal transport protocol - only raw message delivery.
/// Optional methods have default implementations for non-HTTP transports.
public protocol Transport: Actor {
    var logger: Logger { get }

    /// Connect the transport.
    func connect() async throws

    /// Disconnect the transport.
    func disconnect() async

    /// Send raw message data.
    func send(_ data: Data) async throws

    /// Receive messages with optional context.
    func receive() -> AsyncThrowingStream<TransportMessage, Swift.Error>

    // Optional: HTTP-specific methods with defaults

    /// Session ID for multiplexed connections (HTTP only).
    var sessionId: String? { get }

    /// Whether this transport supports server-to-client requests.
    var supportsServerToClientRequests: Bool { get }

    /// Set protocol version after initialization (HTTP only).
    func setProtocolVersion(_ version: String) async

    /// Send with related request ID for response routing (HTTP only).
    func send(_ data: Data, relatedRequestId: RequestId?) async throws
}

// Default implementations - non-HTTP transports get no-op behavior
extension Transport {
    public var sessionId: String? { nil }
    public var supportsServerToClientRequests: Bool { true }

    public func setProtocolVersion(_ version: String) async {
        // Default: no-op for non-HTTP transports
    }

    public func send(_ data: Data, relatedRequestId: RequestId?) async throws {
        // Default: ignore relatedRequestId for non-HTTP transports
        try await send(data)
    }
}
```

**Rationale for this change:** Using a separate `HTTPTransport` protocol requires type-checking (`if let httpTransport = transport as? HTTPTransport`) which is the same problem we're trying to fix. Optional methods with defaults let all code call `setProtocolVersion` without type checks - non-HTTP transports simply ignore it.

### Extracted Message Context

```swift
// Sources/MCP/Base/TransportMessage.swift

/// A message received from transport with optional context.
public struct TransportMessage: Sendable {
    public let data: Data
    public let context: MessageContext?
}

/// Context associated with a received message.
/// Fields are optional - only populated by transports that support them.
public struct MessageContext: Sendable {
    /// Authentication info (HTTP transports with OAuth).
    public let authInfo: AuthInfo?

    /// HTTP request headers.
    public let requestInfo: RequestInfo?

    /// Close SSE stream callback (HTTP SSE only).
    public let closeSSEStream: (@Sendable () async -> Void)?

    /// Close standalone SSE stream callback (HTTP SSE only).
    public let closeStandaloneSSEStream: (@Sendable () async -> Void)?
}
```

### Request Handler Context

```swift
// Sources/MCP/Base/RequestHandlerExtra.swift

/// Context provided to request handlers.
/// Matches TypeScript's RequestHandlerExtra.
public struct RequestHandlerExtra: Sendable {
    /// The JSON-RPC request ID.
    public let requestId: RequestId

    /// Request metadata from _meta field.
    public let _meta: RequestMeta?

    /// Session ID (for HTTP transports).
    public let sessionId: String?

    /// Authentication info (HTTP with OAuth).
    public let authInfo: AuthInfo?

    /// HTTP request headers.
    public let requestInfo: RequestInfo?

    /// Send a notification related to this request.
    public let sendNotification: @Sendable (any NotificationMessageProtocol) async throws -> Void

    /// Send a request related to this request (for bidirectional).
    public let sendRequest: @Sendable (Data) async throws -> Data

    /// Close SSE stream (HTTP SSE only).
    public let closeSSEStream: (@Sendable () async -> Void)?

    /// Close standalone SSE stream (HTTP SSE only).
    public let closeStandaloneSSEStream: (@Sendable () async -> Void)?

    // Convenience properties
    public var taskId: String? { _meta?.relatedTaskId }
    public var isCancelled: Bool { Task.isCancelled }
    public func checkCancellation() throws { try Task.checkCancellation() }
}
```

### Slimmed Client

```swift
// Sources/MCP/Client/Client.swift (refactored)

/// MCP Client - extends MCPProtocol with client-specific behavior.
public actor Client {
    private let protocol: MCPProtocol<
        ClientRequest, ClientNotification, ClientResult,
        ServerRequest, ServerNotification
    >

    // Client-specific state
    public let clientInfo: Client.Info
    public private(set) var serverCapabilities: Server.Capabilities?
    public private(set) var serverInfo: Server.Info?
    public private(set) var protocolVersion: String?
    public private(set) var instructions: String?

    public init(name: String, version: String, ...) {
        clientInfo = .init(name: name, version: version, ...)
        protocol = MCPProtocol()
    }

    public func connect(transport: any Transport) async throws -> Initialize.Result {
        try await protocol.connect(transport: transport)
        return try await initialize()
    }

    // MCP convenience methods delegate to protocol
    public func listTools(params: ListTools.Parameters? = nil) async throws -> ListTools.Result {
        try await protocol.request(ListTools.request(params ?? .init()))
    }

    public func callTool(name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        let result: CallTool.Result = try await protocol.request(
            CallTool.request(.init(name: name, arguments: arguments))
        )
        try await validateToolResult(name, result)
        return result
    }

    // ... other MCP methods
}
```

---

## Implementation Plan

### Phase 0: Preparation and Baseline

**Purpose:** Establish a solid foundation before making structural changes. This phase ensures we can detect regressions.

**Deliverables:**

1. **Regression test suite**
   - Ensure test coverage for all public APIs in Client and Server
   - Add integration tests for full MCP conversation flows if missing

2. **Architecture decision records**
   - Finalize reentrancy handling design (see Risk Assessment)
   - Document how ResponseRouter pattern will integrate
   - Decide on TaskGroup vs unstructured Task for handler management

**Exit criteria:** Reentrancy design finalized; integration approach for existing patterns (ResponseRouter, batch handling, task support) documented

---

### Phase 1: Transport Simplification & Protocol Layer

**Files to create:**
- `Sources/MCP/Base/Protocol.swift`
- `Sources/MCP/Base/RequestHandlerExtra.swift`
- `Sources/MCP/Base/TransportMessage.swift`

**Files to modify:**
- `Sources/MCP/Base/Transport.swift`
- `Sources/MCP/Base/Transports/HTTPServerTransport.swift`
- `Sources/MCP/Base/Transports/HTTPClientTransport.swift`

**Changes:**

1. **Simplify Transport protocol:**
   - Remove HTTP-specific required methods from base protocol
   - Add optional HTTP methods with default no-op implementations
   - Extract `TransportMessage` and `MessageContext` types

2. **Create Protocol layer:**
   - `MCPProtocol` actor with request/response correlation
   - `RequestHandlerExtra` context type
   - Handler registration and invocation
   - Progress callback routing
   - Timeout and cancellation handling

3. **Update HTTP transports:**
   - Override optional HTTP methods with actual implementations
   - Remove any workarounds for base protocol limitations

**Testing milestone:**
- Unit tests for `MCPProtocol` with mock transport
- Request/response correlation tests
- Concurrent request tests
- Timeout and cancellation tests
- Reentrancy scenario tests
- Progress callback routing tests
- All existing transport tests pass

---

### Phase 2: Client & Server Refactoring

**Files to modify:**
- `Sources/MCP/Client/Client.swift`
- `Sources/MCP/Server/Server.swift`

**Changes:**

1. **Refactor Client:**
   - Delegate to internal `MCPProtocol` instance
   - Remove duplicated pending request tracking
   - Rename `RequestHandlerContext` to `RequestHandlerExtra`
   - Remove type-casting to `HTTPClientTransport`

2. **Refactor Server:**
   - Delegate to internal `MCPProtocol` instance
   - Remove duplicated message routing logic
   - Rename `RequestHandlerContext` to `RequestHandlerExtra`
   - Integrate ResponseRouter pattern with Protocol layer

**Testing milestone:**
- All existing Client and Server tests pass (with updated type names)
- Integration tests for full MCP conversation flows
- Capability negotiation tests
- Error propagation verification
- Verify `setProtocolVersion` called correctly for HTTP transports
- Verify stdio transport works without implementing HTTP methods
- Migration guide example for custom transports

---

## Key Design Decisions

### Decision 1: Protocol as Actor vs Class

**Recommendation:** Actor

**Rationale:**
- Aligns with Swift concurrency model
- Client and Server are already actors
- Provides automatic thread safety for shared state
- TypeScript uses a class but JS is single-threaded

### Decision 2: Generic Protocol vs Separate Client/Server Protocols

**Recommendation:** Single generic MCPProtocol with type parameters

**Rationale:**
- Matches TypeScript's approach (`Protocol<SendRequestT, SendNotificationT, SendResultT>`)
- Reduces code duplication
- Client and Server specialize with different type parameters

### Decision 3: Optional Methods vs Separate HTTPTransport Protocol

**Recommendation:** Use optional methods with default implementations on base `Transport`

**Rationale:**
- Matches TypeScript's approach where `sessionId` and `setProtocolVersion` are optional on base `Transport`
- Avoids type-checking (`if let httpTransport = transport as? HTTPTransport`)
- Simpler protocol hierarchy
- Non-HTTP transports get no-op defaults automatically
- Protocol layer can call `setProtocolVersion` unconditionally

**Alternative considered:** Separate `HTTPTransport: Transport` protocol was rejected because it requires the same type-checking pattern we're trying to eliminate.

### Decision 4: Handler Context Unification

**Recommendation:** Single `RequestHandlerExtra` type used by both Client and Server

**Rationale:**
- Matches TypeScript's unified approach
- Reduces API surface area
- Context fields are optional - unused ones are nil
- Client and Server can provide typealiases if desired

### Decision 5: Task Support Integration

**Recommendation:** The Protocol layer must preserve existing task support

**Existing Swift SDK task support:** The Swift SDK already has extensive task support in `Server/Experimental/Tasks/`:
- `TaskStore` and `TaskMessageQueue` interfaces
- Request-scoped `RequestTaskStore`
- `tasks/get`, `tasks/result`, `tasks/list`, `tasks/cancel` handlers
- `input_required` status handling with message queuing
- Related-task metadata propagation

**Requirements for Protocol layer design:**
1. Progress callback infrastructure must support task-style progress reporting
2. Request metadata (`_meta`) must flow through to handlers
3. Cancellation tokens must be properly propagated
4. `RequestHandlerExtra` must include task-related context fields
5. `taskProgressTokens` mapping must be maintained (see Protocol design)

---

## Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Actor reentrancy issues in Protocol | High | High | See detailed reentrancy design below |
| Generic type constraints too complex | Low | Medium | Start simple, add constraints as needed |
| Performance regression from extra layer | Low | Low | Protocol is thin wrapper, minimal overhead |
| Existing task support breaks | Medium | High | Ensure Protocol layer preserves all task hooks |

#### Actor Reentrancy Design

Actor reentrancy is the most significant technical risk in this refactoring. When request handlers call `sendNotification` or `sendRequest`, these operations suspend and can allow other messages to be processed, causing:

- Race conditions between response handling and request sending
- Unexpected interleaving of operations
- Potential deadlocks if not carefully designed

**Context:** TypeScript avoids this issue because JavaScript is single-threaded. Python uses a class with explicit async patterns.

**Recommended approach:**

1. **Separate message loop task**: Run the message receive loop in a dedicated `Task` that posts to the actor, rather than consuming the stream directly within actor-isolated code.

2. **Explicit state management**: Use a state machine pattern for connection lifecycle:
   ```swift
   private enum ConnectionState {
       case disconnected
       case connecting
       case connected(transport: any Transport)
       case disconnecting
   }
   ```

3. **Request tracking isolation**: The `pendingRequests` dictionary should be accessed atomically. Consider whether response handlers need to be invoked outside actor isolation to prevent reentrancy during callback execution.

4. **Handler invocation pattern**: When invoking request handlers:
   ```swift
   // Capture handler and context inside actor
   let handler = requestHandlers[method]
   let context = buildContext(...)

   // Execute handler in separate task to avoid blocking actor
   Task {
       let result = try await handler(params, context)
       await self.sendResponse(result, for: requestId)
   }
   ```

5. **Cancellation coordination**: Ensure that cancellation tokens and timeout controllers are properly cleaned up even when reentrancy occurs.

**Testing requirements:**
- Concurrent request/response scenarios
- Handler that sends notifications mid-execution
- Handler that sends requests mid-execution
- Timeout during handler execution
- Cancellation during handler execution

### Breaking Changes Summary

| Phase | Breaking Changes |
|-------|------------------|
| 0 | None |
| 1 | `Transport` protocol simplified; HTTP-specific methods become optional |
| 2 | `RequestHandlerContext` → `RequestHandlerExtra`; internal Client/Server restructuring |

All breaking changes ship together in the major version release.

### Migration Guide (Major Version)

Since this is a major version bump, breaking changes are acceptable. Users upgrading will need to:

1. **Update handler context types:** `Client.RequestHandlerContext` and `Server.RequestHandlerContext` → `RequestHandlerExtra`

2. **Update custom transport implementations:** The `Transport` protocol changes significantly:
   - `send(_:relatedRequestId:)` → `send(_:)` (HTTP transports override for request routing)
   - HTTP-specific properties (`sessionId`, `supportsServerToClientRequests`) move to optional protocol methods
   - `setProtocolVersion(_:)` becomes an optional protocol method

3. **Review message context usage:** `MessageContext` fields remain but are now clearly documented as HTTP-specific

---

## Testing Strategy

Testing is critical for this refactoring. Each phase should have comprehensive tests before proceeding to the next.

### Phase 0 Tests: Baseline Establishment
- **Regression test audit**: Ensure existing tests cover all critical behaviors
- **Integration test coverage**: Add end-to-end tests for full MCP conversation flows
- **Task support verification**: Tests for existing `Server/Experimental/Tasks/` functionality
- **ResponseRouter tests**: Verify router registration and invocation patterns

### Phase 1 Tests: Transport & Protocol Layer
- **Transport tests**:
  - Unit tests for `TransportMessage` encoding/decoding
  - Verify all transports work with simplified protocol
  - HTTP transports correctly implement optional methods
  - Stdio transport works without HTTP methods
- **Protocol layer tests**:
  - Request/response correlation
  - Concurrent requests handled correctly
  - Timeout handling and cleanup
  - Progress callbacks routed correctly
  - Handler registration and invocation
  - Reentrancy scenarios (handler sends notification/request mid-execution)

### Phase 2 Tests: Client/Server Refactoring
- **Regression tests**: All existing tests pass (with updated type names)
- **Integration tests**: Full MCP conversation flows (initialize, list tools, call tool, etc.)
- **Error handling**: Verify error propagation unchanged
- **Capability negotiation**: Client/server capability exchange works correctly
- **ResponseRouter integration**: Verify task result routing still works

### Test Infrastructure Requirements
- Mock transport for unit testing Protocol layer
- Test fixtures for common MCP message sequences
- Concurrency stress tests using Swift Testing's parallelism features

---

## Summary

### Overall Assessment

The Swift MCP SDK has a solid foundation but would benefit significantly from introducing a Protocol layer. The current architecture conflates transport concerns with protocol mechanics, leading to leaked abstractions and duplicated code.

### Critical Path

1. **Phase 0:** Finalize architectural decisions (reentrancy design, ResponseRouter integration)
2. **Phase 1:** Simplify Transport protocol and create Protocol layer
3. **Phase 2:** Refactor Client and Server to use Protocol layer

### Key Tradeoffs

| Decision | Tradeoff |
|----------|----------|
| Protocol as Actor | Safer concurrency vs. potential reentrancy complexity (see Risk Assessment) |
| Optional HTTP methods on Transport | Simpler protocol hierarchy vs. non-HTTP transports carry unused default methods |
| Generic MCPProtocol | Code reuse vs. type complexity |

### Evolution Path

After this refactoring:
- Adding new transports becomes simpler (implement minimal Transport protocol)
- HTTP-specific features are isolated and can evolve independently
- Client and Server focus on MCP semantics, not message routing
- Task support can be cleanly added to Protocol layer

### Immediate Red Flags

1. **Type casting to HTTPClientTransport in Client.swift** - This should be addressed immediately as it couples Client to a specific transport implementation

2. **Duplicated pending request tracking** - Both Client and Server have nearly identical `AnyPendingRequest` and tracking logic that should be unified

3. **MessageContext fields unused by stdio transport** - All transports must carry HTTP-specific fields even when irrelevant

### Additional Concerns Identified in Review

4. **Actor reentrancy design not detailed** - Before coding begins, a detailed design for how the actor handles concurrent operations must be completed (see Risk Assessment section)

5. **Message loop ownership undefined** - Need to clarify whether the message loop runs inside or outside the actor boundary, and how `receive()` stream consumption coordinates with handler execution

6. **ResponseRouter pattern not addressed** - The existing `ResponseRouter` protocol in Server.swift is used for task result handling. The Protocol layer must provide hooks for router registration or absorb this functionality (see Gap 1)

7. **Batch request handling not addressed** - The `Server.Batch` type supports batch requests but the plan doesn't specify whether batching is handled at transport or Protocol level (see Gap 2)

8. **Type parameter count mismatch with TypeScript** - The proposed `MCPProtocol` has 5 type parameters but TypeScript's Protocol only has 3 (what you send). Evaluate whether 5 parameters is necessary or over-constrains the design

### Recommendation

**Proceed with implementation.** The architecture is sound. Since this is a major version release, all breaking changes can ship together without incremental migration concerns.

**Before coding (Phase 0):**
1. Finalize reentrancy handling design (highest-risk area)
2. Decide ResponseRouter integration approach
3. Clarify batch handling boundary
4. Evaluate whether 5 type parameters is necessary

**Implementation order:**
1. Simplify Transport protocol and create Protocol layer (Phase 1)
2. Refactor Client and Server to use Protocol layer (Phase 2)

The refactoring will improve the codebase's maintainability. The main complexity is actor reentrancy design, which should be finalized before implementation begins.

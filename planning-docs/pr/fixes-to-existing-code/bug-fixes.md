# Bug Fixes in PR #175

The following are improvements made to the existing codebase in PR [#175](https://github.com/modelcontextprotocol/swift-sdk/pull/175), not including new functionality that was added in the PR.

## Critical Bug Fixes

### 1. Client Receive Loop Re-consuming AsyncThrowingStream (PR #170)

**Issue**: The client was calling `connection.receive()` inside a `repeat { } while true` loop, meaning it tried to iterate the same async stream multiple times. AsyncThrowingStreams can only be iterated once.

**Before (buggy)**:
```swift
repeat {
    let stream = await connection.receive()  // ❌ Called on each iteration
    for try await data in stream { ... }
} while true
```

**After (fixed)**:
```swift
let stream = await connection.receive()  // ✅ Called once
for try await transportMessage in stream { ... }
```

**Location**: `Sources/MCP/Client/Client.swift`

---

### 2. Client Receive Loop Spinning After Transport Closes (PR #171)

**Issue**: When an MCP server process exited, the client kept looping even though the underlying stream had finished. This resulted in a tight loop consuming ~100% CPU per disconnected server.

**Fix**: Removed the `repeat { } while true` wrapper. The receive loop now exits naturally when the stream ends, and includes a `defer` block to clean up pending requests on unexpected disconnection.

**Additional fix**: Added proper cleanup of pending requests when the transport closes unexpectedly via `cleanUpPendingRequestsOnUnexpectedDisconnect()`.

**Location**: `Sources/MCP/Client/Client.swift`

---

### 3. NetworkTransport Crash on Reconnect (Issue #137)

**Issue**: `continuation.resume(throwing:)` could be called multiple times for the same continuation, causing a runtime crash. This happened during reconnection scenarios when `handleReconnection()` scheduled a delayed retry via `Task` while other code paths could also resume the continuation.

**Before (buggy)**:
```swift
private var connectionContinuationResumed = false  // ❌ Race-prone boolean flag

connection.stateUpdateHandler = { state in
    Task { @MainActor in
        switch state {
        case .ready:
            await self.handleConnectionReady(continuation: continuation)
        case .failed(let error):
            await self.handleConnectionFailed(error: error, continuation: continuation)
        // ...
        }
    }
}
```

**After (fixed)**:
```swift
// Use AsyncStream to safely bridge callback-based state updates to async/await
let stateStream = AsyncStream<NWConnection.State> { continuation in
    connection.stateUpdateHandler = { state in
        continuation.yield(state)
        // Finish stream on terminal states
        switch state {
        case .ready, .failed, .cancelled:
            continuation.finish()
        default:
            break
        }
    }
}

for await state in stateStream {
    switch state {
    case .ready: return
    case .failed(let error): throw error
    // ...
    }
}
```

**Key changes**:
- Replaced boolean flag tracking with `AsyncStream` pattern for safe continuation handling
- Removed `handleReconnection()`, `handleConnectionReady()`, `handleConnectionFailed()`, `handleConnectionCancelled()` methods (error-prone multi-path continuation handling)
- Connection state changes are now processed sequentially via `waitForConnectionReady()` using `AsyncStream`

**Location**: `Sources/MCP/Base/Transports/NetworkTransport.swift`

---

## InMemoryTransport Fixes

### 4. InMemoryTransport Race Condition with Message Queue

**Issue**: `InMemoryTransport` had a message queue that could lead to race conditions when messages arrived before the stream was consumed.

**Before (racy)**:
```swift
private var incomingMessages: [Data] = []
private var messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation?

func receive() -> AsyncThrowingStream<Data, Swift.Error> {
    return AsyncThrowingStream { continuation in
        self.messageContinuation = continuation
        // Deliver any queued messages
        for message in self.incomingMessages {
            continuation.yield(message)
        }
        self.incomingMessages.removeAll()
        // ...
    }
}
```

**After (fixed)**:
```swift
private let messageStream: AsyncThrowingStream<TransportMessage, Swift.Error>
private let messageContinuation: AsyncThrowingStream<TransportMessage, Swift.Error>.Continuation

init(...) {
    let (stream, continuation) = AsyncThrowingStream<TransportMessage, Swift.Error>.makeStream()
    self.messageStream = stream
    self.messageContinuation = continuation
}

func receive() -> AsyncThrowingStream<TransportMessage, Swift.Error> {
    return messageStream
}
```

**Location**: `Sources/MCP/Base/Transports/InMemoryTransport.swift`

---

## StdioTransport Fixes

### 5. StdioTransport Didn't Handle CRLF Line Endings

**Issue**: Windows-style line endings (CRLF) weren't properly handled, potentially leaving carriage returns in message data.

**Before**:
```swift
while let newlineIndex = pendingData.firstIndex(of: UInt8(ascii: "\n")) {
    let messageData = pendingData[..<newlineIndex]
    // No CRLF handling
}
```

**After**:
```swift
while let newlineIndex = pendingData.firstIndex(of: UInt8(ascii: "\n")) {
    var messageData = pendingData[..<newlineIndex]
    pendingData = pendingData[(newlineIndex + 1)...]

    // Strip trailing carriage return for Windows-style line endings (CRLF)
    if messageData.last == UInt8(ascii: "\r") {
        messageData = messageData.dropLast()
    }
    // ...
}
```

**Location**: `Sources/MCP/Base/Transports/StdioTransport.swift`

---

## Error Handling Fixes

### 6. MCPError Equality Was Code-Only Comparison

**Issue**: `MCPError` equality compared only the error code, meaning different errors with the same code were considered equal.

**Before**:
```swift
public static func == (lhs: MCPError, rhs: MCPError) -> Bool {
    lhs.code == rhs.code  // ❌ Only compares code
}
```

**After**:
```swift
public static func == (lhs: MCPError, rhs: MCPError) -> Bool {
    switch (lhs, rhs) {
    case (.parseError(let l), .parseError(let r)):
        return l == r
    case (.invalidRequest(let l), .invalidRequest(let r)):
        return l == r
    // ... full comparison of all cases and associated values
    default:
        return false
    }
}
```

**Location**: `Sources/MCP/Base/Error.swift`

---

### 7. MCPError Encoding Used errorDescription Instead of Raw Message

**Issue**: Error encoding used `errorDescription` (which includes prefixes like "Server error:") instead of the raw message for wire format.

**Before**:
```swift
try container.encode(errorDescription ?? "Unknown error", forKey: .message)
```

**After**:
```swift
try container.encode(message, forKey: .message)  // Uses new `message` property
```

Added new `message` property that returns the raw message suitable for JSON-RPC serialization.

**Location**: `Sources/MCP/Base/Error.swift`

---

## Security Fix

### 8. Information Disclosure via Error Messages

**Vulnerability**: The server was leaking internal error details to clients via `error.localizedDescription` when non-MCP errors occurred during request handling.

**Risk**: `localizedDescription` could contain sensitive information such as:
- File paths revealing server directory structure
- Database connection strings or queries
- Internal implementation details
- Stack traces or debugging information

**Before (vulnerable)**:
```swift
} catch {
    let response = AnyMethod.response(
        id: requestID ?? .random,
        error: error as? MCPError
            ?? MCPError.internalError(error.localizedDescription)  // ❌ Leaks internal details
    )
    try? await send(response)
}
```

**After (fixed)**:
```swift
} catch {
    // Sanitize non-MCP errors to avoid leaking internal details to clients
    let response = AnyMethod.response(
        id: requestID ?? .random,
        error: error as? MCPError
            ?? MCPError.internalError("An internal error occurred")  // ✅ Sanitized
    )
    try? await send(response)
}
```

The same fix was applied to `TypedClientRequestHandler` in `Messages.swift` for client-side request handling.

**Locations**:
- `Sources/MCP/Server/Server.swift`
- `Sources/MCP/Base/Messages.swift`

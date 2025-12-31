# Code Quality Improvements in PR #175

The following are improvements made to the existing codebase in PR [#175](https://github.com/modelcontextprotocol/swift-sdk/pull/175), not including new functionality that was added in the PR.

## Type Safety Improvements

### 1. Removed Force Casts in Message Decoding

**Issue**: The message decoding logic used force casts (`as!`) which could crash at runtime if types didn't match.

**Before**:
```swift
params =
    (try container.decodeIfPresent(M.Parameters.self, forKey: .params)
        ?? (M.Parameters.self as! NotRequired.Type).init() as! M.Parameters)
```

**After**:
```swift
if let decoded = try container.decodeIfPresent(M.Parameters.self, forKey: .params) {
    params = decoded
} else if let notRequiredType = M.Parameters.self as? NotRequired.Type,
    let defaultValue = notRequiredType.init() as? M.Parameters
{
    params = defaultValue
} else {
    throw DecodingError.dataCorrupted(...)
}
```

**Locations**: `Sources/MCP/Base/Messages.swift` (Request and Message decoding)

---

### 2. Replaced Force Unwrap on Version.latest

**Issue**: `Version.latest` used force unwrap on `Set.max()` result.

**Before**:
```swift
public static let latest = supported.max()!
```

**After**:
```swift
public static let v2025_11_25 = "2025-11-25"
// ...
public static let latest = v2025_11_25
```

**Location**: `Sources/MCP/Base/Versioning.swift`

---

### 3. StopReason as RawRepresentable (Open String Type)

**Issue**: Stop reasons were not easily extensible for provider-specific values.

**Before**: Used plain string or enum.

**After**:
```swift
public struct StopReason: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    // Standard values
    public static let endTurn = StopReason(rawValue: "endTurn")
    public static let stopSequence = StopReason(rawValue: "stopSequence")
    public static let maxTokens = StopReason(rawValue: "maxTokens")
    public static let toolUse = StopReason(rawValue: "toolUse")
}
```

**Location**: `Sources/MCP/Client/Sampling.swift`

---

## API Design Improvements

### 4. ID Renamed to RequestId for Clarity

**Issue**: The code used a generic `ID` type for request identifiers, which was unclear.

**Before**:
```swift
public enum ID: Hashable, Sendable { ... }

public struct Request<M: Method>: ... {
    public let id: ID
}
```

**After**:
```swift
public enum RequestId: Hashable, Sendable { ... }

@available(*, deprecated, renamed: "RequestId")
public typealias ID = RequestId  // Backwards compatibility

public struct Request<M: Method>: ... {
    public let id: RequestId  // Clear semantic meaning
}
```

**Location**: `Sources/MCP/Base/ID.swift` renamed to `Sources/MCP/Base/RequestId.swift`

---

### 5. Convenience Initializers for Content Types

**Issue**: Adding annotations and metadata to content types made the simple cases verbose.

**After**: Added convenience factory methods:

```swift
public enum Content: Hashable, Codable, Sendable {
    case text(String, annotations: ContentAnnotations?, _meta: [String: Value]?)
    // ...

    // Convenience initializers (backwards compatibility)
    public static func text(_ text: String) -> Content {
        .text(text, annotations: nil, _meta: nil)
    }

    public static func image(data: String, mimeType: String) -> Content {
        .image(data: data, mimeType: mimeType, annotations: nil, _meta: nil)
    }
}
```

**Locations**: `Sources/MCP/Server/Tools.swift`, `Sources/MCP/Server/Prompts.swift`

---

## Code Organization

### 6. Version Constants Extracted

**Issue**: Version strings were inline in a Set, making them hard to reference.

**Before**:
```swift
static let supported: Set<String> = [
    "2025-03-26",
    "2024-11-05",
]
```

**After**:
```swift
public static let v2025_11_25 = "2025-11-25"
public static let v2025_06_18 = "2025-06-18"
public static let v2025_03_26 = "2025-03-26"
public static let v2024_11_05 = "2024-11-05"

public static let supported: Set<String> = [
    v2025_11_25, v2025_06_18, v2025_03_26, v2024_11_05,
]

public static let defaultNegotiated = v2025_03_26  // Per spec for missing header
```

**Location**: `Sources/MCP/Base/Versioning.swift`

---

### 7. Error Codes Centralized

**Issue**: Error codes were scattered as magic numbers throughout the codebase.

**After**: Created centralized `ErrorCode` enum:

```swift
public enum ErrorCode {
    // Standard JSON-RPC 2.0 Errors
    public static let parseError: Int = -32700
    public static let invalidRequest: Int = -32600
    public static let methodNotFound: Int = -32601
    public static let invalidParams: Int = -32602
    public static let internalError: Int = -32603

    // MCP Specification Errors
    public static let resourceNotFound: Int = -32002
    public static let urlElicitationRequired: Int = -32042

    // SDK-Specific Errors
    public static let connectionClosed: Int = -32000
    public static let requestTimeout: Int = -32001
    public static let transportError: Int = -32003
    public static let requestCancelled: Int = -32004
}
```

**Location**: `Sources/MCP/Base/Error.swift`

---

### 8. HTTP Header Constants

**Issue**: HTTP header names were string literals throughout the code.

**After**: Created centralized `HTTPHeader` enum:

```swift
public enum HTTPHeader {
    public static let contentType = "content-type"
    public static let accept = "accept"
    public static let sessionId = "mcp-session-id"
    public static let protocolVersion = "mcp-protocol-version"
    // ...
}
```

**Location**: `Sources/MCP/Base/HTTPHeader.swift`

---

## Concurrency Pattern Improvements

### 9. Simplified NetworkTransport Send Completion Handler

**Improvement**: The send completion handler used a `Task { @MainActor in }` wrapper and a boolean flag to track whether the continuation had been resumed. Since `NWConnection.send`'s completion handler is called exactly once per operation, this defensive code was unnecessary.

**Before**:
```swift
var sendContinuationResumed = false

connection.send(...) { error in
    Task { @MainActor in
        if !sendContinuationResumed {
            sendContinuationResumed = true
            // complex reconnection logic
            continuation.resume(...)
        }
    }
}
```

**After**:
```swift
connection.send(...) { [weak self] error in
    guard let self else { return }
    if let error {
        self.logger.error("Send error: \(error)")
        if error.isConnectionLost && self.reconnectionConfig.enabled {
            Task {
                await self.setIsConnected(false)
                try? await Task.sleep(for: .milliseconds(500))
                if await !self.isStopping {
                    self.connection.cancel()
                    try? await self.connect()
                }
            }
        }
        continuation.resume(throwing: MCPError.internalError("Send error: \(error)"))
    } else {
        continuation.resume()
    }
}
```

**Benefits**: Simpler control flow, removes unnecessary actor hop, easier to reason about.

**Location**: `Sources/MCP/Base/Transports/NetworkTransport.swift`

---

### 10. Simplified NetworkTransport Receive Completion Handler

**Improvement**: Similar to the send handler, the receive completion handler used a `Task { @MainActor in }` wrapper and boolean flag. Since `NWConnection.receive`'s completion handler is also called exactly once per operation, this was simplified.

**Before**:
```swift
var receiveContinuationResumed = false

connection.receive(...) { content, _, isComplete, error in
    Task { @MainActor in
        if !receiveContinuationResumed {
            receiveContinuationResumed = true
            // ...
        }
    }
}
```

**After**:
```swift
connection.receive(...) { [weak self] content, _, isComplete, error in
    if let error {
        continuation.resume(throwing: MCPError.transportError(error))
    } else if let content {
        continuation.resume(returning: content)
    } else if isComplete {
        self?.logger.trace("Connection completed by peer")
        continuation.resume(throwing: MCPError.connectionClosed)
    } else {
        continuation.resume(returning: Data())
    }
}
```

**Benefits**: Removes unnecessary indirection, cleaner error handling paths.

**Location**: `Sources/MCP/Base/Transports/NetworkTransport.swift`

---

### 11. AsyncThrowingStream Creation Using makeStream()

**Improvement**: Multiple transports used the pattern `var continuation: ...; stream = AsyncThrowingStream { continuation = $0 }`. While this works correctly (the closure is called synchronously), the `makeStream()` API introduced in Swift 5.9 is cleaner and more explicit.

**Before**:
```swift
var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
self.messageStream = AsyncThrowingStream { continuation = $0 }
self.messageContinuation = continuation
```

**After**:
```swift
let (stream, continuation) = AsyncThrowingStream<TransportMessage, Swift.Error>.makeStream()
self.messageStream = stream
self.messageContinuation = continuation
```

**Benefits**: No force-unwrapped optional, clearer intent, leverages modern Swift API.

**Note**: The stream type also changed from `Data` to `TransportMessage` as part of the transport layer refactoring.

**Locations**:
- `Sources/MCP/Base/Transports/NetworkTransport.swift`
- `Sources/MCP/Base/Transports/HTTPClientTransport.swift`
- `Sources/MCP/Base/Transports/InMemoryTransport.swift`
- `Sources/MCP/Base/Transports/StdioTransport.swift`

---

### 12. HTTPClientTransport Session ID Signal Using AsyncStream

**Improvement**: The SSE streaming task needed to wait for a session ID before proceeding. The original implementation used a `Task` that suspended in `withCheckedContinuation`, storing the continuation for later resumption. This pattern, while functional (with a timeout fallback), was replaced with the cleaner `AsyncStream` pattern.

**Before**:
```swift
private var initialSessionIDSignalTask: Task<Void, Never>?
private var initialSessionIDContinuation: CheckedContinuation<Void, Never>?

private func setupInitialSessionIDSignal() {
    self.initialSessionIDSignalTask = Task {
        await withCheckedContinuation { continuation in
            self.initialSessionIDContinuation = continuation
        }
    }
}
```

**After**:
```swift
private var sessionIDSignalStream: AsyncStream<Void>?
private var sessionIDSignalContinuation: AsyncStream<Void>.Continuation?

private func setUpInitialSessionIDSignal() {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    self.sessionIDSignalStream = stream
    self.sessionIDSignalContinuation = continuation
}
```

**Benefits**: Cleaner signaling pattern, no Task wrapper needed, consistent with other stream-based patterns in the codebase.

**Location**: `Sources/MCP/Base/Transports/HTTPClientTransport.swift`

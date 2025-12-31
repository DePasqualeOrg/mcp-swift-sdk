# Per-message context for request handlers

Request handlers can now access per-request context via `RequestHandlerContext`:

```swift
server.withRequestHandler(CallTool.self) { params, context in
    // Authentication (when using authenticated transports)
    if let auth = context.authInfo {
        guard auth.scopes.contains("tools:execute") else {
            throw MCPError.invalidRequest("Insufficient scope")
        }
    }

    // SSE stream control (when using SSE transports)
    await context.closeSSEStream?()

    // Session identifier (for per-session features like log levels)
    print("Session: \(context.sessionId ?? "none")")

    return result
}
```

The transport layer now passes context with each message via `TransportMessage`, ensuring context stays associated with the correct request even under concurrent load.

**Breaking change for custom transports**: `receive()` now returns `AsyncThrowingStream<TransportMessage, Error>`. Wrap data with: `TransportMessage(data: data)`

// Copyright © Anthony DePasquale

/// Transport options for running an MCPServer.
///
/// Use this enum with `MCPServer.run(transport:)` to start a server
/// with a common transport configuration.
///
/// Example:
/// ```swift
/// // Standard I/O (most common for CLI tools)
/// try await server.run(transport: .stdio)
///
/// // Custom transport
/// let myTransport = MyCustomTransport()
/// try await server.run(transport: .custom(myTransport))
/// ```
///
/// For HTTP servers with multiple clients, use `MCPServer.createSession()` instead
/// of `run(transport:)`. See `MCPHTTPHandler` for a convenient wrapper.
public enum TransportType: Sendable {
    /// Standard I/O transport (stdin/stdout).
    ///
    /// This is the most common transport for MCP servers that run as
    /// command-line tools invoked by clients like Claude Desktop.
    case stdio

    /// Custom transport for advanced use cases.
    ///
    /// Use this when you need a transport not covered by the built-in options,
    /// such as `InMemoryTransport` for testing or a custom network transport.
    case custom(any Transport)
}

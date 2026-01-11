/// Context for DSL tools - wraps `RequestHandlerContext` with a tool-friendly API.
///
/// Always passed to `perform(context:)`. Tools can use it for:
/// - Progress reporting during long-running operations
/// - Logging at various levels (info, debug, warning, error)
/// - Checking for request cancellation
///
/// Example:
/// ```swift
/// func perform(context: ToolContext) async throws -> String {
///     for (index, item) in items.enumerated() {
///         try context.checkCancellation()
///         try await context.reportProgress(Double(index), total: Double(items.count))
///         try await context.info("Processing item \(index)")
///         // ... process item
///     }
///     return "Processed \(items.count) items"
/// }
/// ```
public struct ToolContext: Sendable {
    private let handlerContext: Server.RequestHandlerContext
    private let progressToken: ProgressToken?

    /// Creates a new tool context.
    /// - Parameters:
    ///   - handlerContext: The underlying request handler context.
    ///   - progressToken: Optional progress token from the request metadata.
    public init(handlerContext: Server.RequestHandlerContext, progressToken: ProgressToken? = nil) {
        self.handlerContext = handlerContext
        self.progressToken = progressToken
    }

    // MARK: - Cancellation

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
    /// Silently returns without error if the request didn't include a progress token.
    /// - Parameters:
    ///   - progress: The current progress value.
    ///   - total: The total value (optional).
    ///   - message: A human-readable progress message (optional).
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
    /// - Parameter message: The message to log.
    public func info(_ message: String) async throws {
        try await handlerContext.sendLogMessage(level: LoggingLevel.info, data: Value.string(message))
    }

    /// Log at debug level.
    /// - Parameter message: The message to log.
    public func debug(_ message: String) async throws {
        try await handlerContext.sendLogMessage(level: LoggingLevel.debug, data: Value.string(message))
    }

    /// Log at warning level.
    /// - Parameter message: The message to log.
    public func warning(_ message: String) async throws {
        try await handlerContext.sendLogMessage(level: LoggingLevel.warning, data: Value.string(message))
    }

    /// Log at error level.
    /// - Parameter message: The message to log.
    public func error(_ message: String) async throws {
        try await handlerContext.sendLogMessage(level: LoggingLevel.error, data: Value.string(message))
    }

    // MARK: - Request Info

    /// The request ID for this tool invocation.
    public var requestId: RequestId {
        handlerContext.requestId
    }

    /// The session ID, if available.
    public var sessionId: String? {
        handlerContext.sessionId
    }
}

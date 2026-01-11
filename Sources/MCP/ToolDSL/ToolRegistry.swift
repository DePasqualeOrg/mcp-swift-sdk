/// A registry for managing `@Tool`-decorated types.
///
/// `ToolRegistry` stores registered tool types and provides:
/// - Tool definitions for `ListTools` responses
/// - Tool execution with automatic parsing
///
/// Example:
/// ```swift
/// // Create registry with result builder
/// let registry = ToolRegistry {
///     GetWeather.self
///     CreateEvent.self
///     DeleteEvent.self
/// }
///
/// // Or register dynamically
/// let registry = ToolRegistry()
/// await registry.register(GetWeather.self)
/// ```
///
/// The registry handles parsing arguments into typed instances and
/// executing the tool. Input validation is performed by the Server
/// before calling the registry.
public actor ToolRegistry {
    private var tools: [String: any ToolSpec.Type] = [:]

    /// Creates an empty registry.
    public init() {}

    /// Creates a registry with the specified tools.
    ///
    /// Example:
    /// ```swift
    /// let registry = ToolRegistry {
    ///     GetWeather.self
    ///     CreateEvent.self
    /// }
    /// ```
    public init(@ToolBuilder tools: () -> [any ToolSpec.Type]) {
        let toolList = tools()
        self.tools = Dictionary(uniqueKeysWithValues: toolList.map {
            ($0.toolDefinition.name, $0)
        })
    }

    /// Registers a tool type.
    ///
    /// - Parameter tool: The tool type to register.
    public func register<T: ToolSpec>(_ tool: T.Type) {
        tools[T.toolDefinition.name] = tool
    }

    /// All tool definitions for `ListTools` response.
    public var definitions: [Tool] {
        tools.values.map { $0.toolDefinition }
    }

    /// Checks if the registry handles a tool with the given name.
    ///
    /// - Parameter name: The tool name to check.
    /// - Returns: `true` if the registry contains the tool.
    public func hasTool(_ name: String) -> Bool {
        tools[name] != nil
    }

    /// Executes a tool.
    ///
    /// This method assumes input validation has already been performed
    /// by the Server. It parses the arguments into a typed instance
    /// and executes the tool.
    ///
    /// - Parameters:
    ///   - name: The tool name to execute.
    ///   - arguments: The tool arguments.
    ///   - context: The tool context for progress reporting and logging.
    /// - Returns: The tool execution result.
    /// - Throws: `MCPError.methodNotFound` if the tool doesn't exist,
    ///           or any error from parsing or execution.
    public func execute(
        _ name: String,
        arguments: [String: Value]?,
        context: ToolContext
    ) async throws -> CallTool.Result {
        guard let toolType = tools[name] else {
            throw MCPError.methodNotFound("Unknown tool: \(name)")
        }

        // Parse into typed instance (Server already validated)
        let instance = try toolType.parse(from: arguments)

        // Execute and convert output
        let output = try await instance.perform(context: context)
        return try output.toCallToolResult()
    }
}

// MARK: - Result Builder

/// A result builder for collecting tool types.
///
/// Example:
/// ```swift
/// let registry = ToolRegistry {
///     GetWeather.self
///     CreateEvent.self
///     if includeDelete {
///         DeleteEvent.self
///     }
/// }
/// ```
@resultBuilder
public struct ToolBuilder {
    public static func buildBlock(_ tools: [any ToolSpec.Type]...) -> [any ToolSpec.Type] {
        tools.flatMap { $0 }
    }

    public static func buildOptional(_ tool: [any ToolSpec.Type]?) -> [any ToolSpec.Type] {
        tool ?? []
    }

    public static func buildEither(first tool: [any ToolSpec.Type]) -> [any ToolSpec.Type] {
        tool
    }

    public static func buildEither(second tool: [any ToolSpec.Type]) -> [any ToolSpec.Type] {
        tool
    }

    public static func buildArray(_ tools: [[any ToolSpec.Type]]) -> [any ToolSpec.Type] {
        tools.flatMap { $0 }
    }

    public static func buildExpression(_ tool: any ToolSpec.Type) -> [any ToolSpec.Type] {
        [tool]
    }
}

// Copyright © Anthony DePasquale

/// A prompt that can be rendered via MCP.
///
/// Conformance is typically added by the `@Prompt` macro, which generates:
/// - `promptDefinition`: The `Prompt` definition including name, description, and arguments
/// - `parse(from:)`: Parsing validated arguments into a typed instance
/// - `init()`: Required empty initializer
/// - `render(context:)`: Bridging method (only if you write `render()` without context)
///
/// Use the `@Prompt` macro for prompts known at compile time. For prompts
/// discovered at runtime (from config files, databases, plugins), use
/// `MCPServer.registerPrompt(name:arguments:handler:)` instead.
///
/// ## Basic Usage
///
/// Most prompts don't need access to `HandlerContext`. Just write `render()` without parameters:
///
/// ```swift
/// @Prompt
/// struct GreetingPrompt {
///     static let name = "greeting"
///     static let description = "Greet a user"
///
///     @Argument(description: "Name of the person")
///     var name: String
///
///     func render() async throws -> [Prompt.Message] {
///         [.user("Hello, \(name)! How can I help you?")]
///     }
/// }
/// ```
///
/// ## Using HandlerContext
///
/// If your prompt needs to log messages or access request metadata,
/// include the `context` parameter:
///
/// ```swift
/// @Prompt
/// struct InterviewPrompt {
///     static let name = "interview"
///     static let description = "Conduct a technical interview"
///
///     @Argument(description: "Name of the candidate")
///     var candidateName: String
///
///     @Argument(description: "The job role")
///     var role: String?
///
///     func render(context: HandlerContext) async throws -> [Prompt.Message] {
///         try await context.log(level: .info, message: "Starting interview for \(candidateName)")
///         return [
///             .user("You are interviewing \(candidateName) for the \(role ?? "Software Engineer") role."),
///             .assistant("Hello \(candidateName)! Let's begin the interview.")
///         ]
///     }
/// }
/// ```
public protocol PromptSpec: Sendable {
    /// The result type returned by `render(context:)`.
    associatedtype Output: PromptOutput

    /// The Prompt definition including name, description, and arguments.
    static var promptDefinition: Prompt { get }

    /// Parse validated arguments into a typed instance.
    /// Called after argument validation has passed.
    /// - Parameter arguments: The string arguments dictionary from the client.
    /// - Returns: A configured instance of this prompt.
    /// - Throws: `MCPError.invalidParams` if required arguments are missing.
    static func parse(from arguments: [String: String]?) throws -> Self

    /// Renders the prompt with typed arguments.
    ///
    /// - Parameter context: Provides logging, progress reporting, and request metadata.
    /// - Returns: The prompt's output, which will be converted to a `GetPrompt.Result`.
    /// - Throws: Any error to indicate prompt failure.
    func render(context: HandlerContext) async throws -> Output

    /// Required empty initializer for instance creation during parsing.
    /// Generated automatically by the `@Prompt` macro.
    init()
}

// The @Prompt macro is provided by the MCPTool module.
// Import MCPTool alongside MCP to define prompts:
//
//     import MCP
//     import MCPTool
//
//     @Prompt
//     struct MyPrompt { ... }

/// A prompt that can be rendered via MCP.
///
/// Conformance is typically added by the `@Prompt` macro, which generates:
/// - `promptDefinition`: The `Prompt` definition including name, description, and arguments
/// - `parse(from:)`: Parsing validated arguments into a typed instance
/// - `init()`: Required empty initializer
///
/// Use the `@Prompt` macro for prompts known at compile time. For prompts
/// discovered at runtime (from config files, databases, plugins), use
/// `MCPServer.registerPrompt(name:arguments:handler:)` instead.
///
/// Example:
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
///         [
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

/// Macro that generates `PromptSpec` conformance for a struct.
///
/// The macro generates:
/// - `promptDefinition` with arguments derived from `@Argument` properties
/// - `parse(from:)` for converting string arguments to typed properties
/// - `init()` empty initializer
/// - `PromptSpec` protocol conformance
///
/// Use this macro for prompts known at compile time. For prompts discovered
/// at runtime (from config files, databases, plugins), use
/// `MCPServer.registerPrompt(name:arguments:handler:)` instead.
///
/// Example:
/// ```swift
/// @Prompt
/// struct CodeReviewPrompt {
///     static let name = "code_review"
///     static let description = "Review code changes"
///     static let title = "Code Review"  // Optional display title
///
///     @Argument(description: "The code to review")
///     var code: String
///
///     @Argument(description: "Programming language")
///     var language: String?
///
///     func render(context: HandlerContext) async throws -> [Prompt.Message] {
///         var messages: [Prompt.Message] = [
///             .user("Please review this code:")
///         ]
///         if let lang = language {
///             messages.append(.user("Language: \(lang)"))
///         }
///         messages.append(.user(code))
///         return messages
///     }
/// }
/// ```
@attached(member, names: named(promptDefinition), named(parse), named(init))
@attached(extension, conformances: PromptSpec)
public macro Prompt() = #externalMacro(module: "MCPMacros", type: "PromptMacro")

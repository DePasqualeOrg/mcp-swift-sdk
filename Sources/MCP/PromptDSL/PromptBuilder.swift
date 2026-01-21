// Copyright © Anthony DePasquale

/// A result builder for collecting prompt types.
///
/// Use this builder to register multiple prompts at once with conditional logic.
///
/// Example:
/// ```swift
/// try await server.register {
///     InterviewPrompt.self
///     CodeReviewPrompt.self
///     if includeAdvanced {
///         AdvancedPrompt.self
///     }
/// }
/// ```
@resultBuilder
public struct PromptBuilder {
    public static func buildBlock(_ prompts: [any PromptSpec.Type]...) -> [any PromptSpec.Type] {
        prompts.flatMap { $0 }
    }

    public static func buildOptional(_ prompt: [any PromptSpec.Type]?) -> [any PromptSpec.Type] {
        prompt ?? []
    }

    public static func buildEither(first prompt: [any PromptSpec.Type]) -> [any PromptSpec.Type] {
        prompt
    }

    public static func buildEither(second prompt: [any PromptSpec.Type]) -> [any PromptSpec.Type] {
        prompt
    }

    public static func buildArray(_ prompts: [[any PromptSpec.Type]]) -> [any PromptSpec.Type] {
        prompts.flatMap { $0 }
    }

    public static func buildExpression(_ prompt: any PromptSpec.Type) -> [any PromptSpec.Type] {
        [prompt]
    }
}

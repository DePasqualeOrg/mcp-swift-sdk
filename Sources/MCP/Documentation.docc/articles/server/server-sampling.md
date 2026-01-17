# Sampling

Request LLM completions from MCP clients

## Overview

Sampling enables servers to request LLM completions from clients. The client handles the actual model interaction while the server focuses on its domain logic. This is useful when your server needs AI assistance to process data or generate content.

> Note: Sampling is a client capability, not a server capability. Your server requests sampling from clients that support it.

> Important: Client implementations should include human-in-the-loop controls. Users should be able to review and approve sampling requests, view prompts before sending, and review responses before delivery. Design your server with the expectation that users may modify or reject requests.

## Basic Sampling

Request a completion using ``Server/createMessage(_:)``:

```swift
await server.withRequestHandler(CallTool.self) { [server] params, context in
    guard params.name == "summarize" else { ... }

    let data = params.arguments?["data"]?.stringValue ?? ""

    let result = try await server.createMessage(
        CreateSamplingMessage.Parameters(
            messages: [.user(.text("Summarize this data: \(data)"))],
            maxTokens: 500
        )
    )

    // Extract the response (content is a single block for basic sampling)
    if case .text(let summary, _, _) = result.content {
        return CallTool.Result(content: [.text(summary)])
    }

    return CallTool.Result(content: [.text("Failed to generate summary")], isError: true)
}
```

## Sampling Parameters

Configure the sampling request:

```swift
let result = try await server.createMessage(
    CreateSamplingMessage.Parameters(
        messages: [
            .user(.text("Translate to Spanish: Hello, world!"))
        ],
        modelPreferences: ModelPreferences(
            hints: [.init(name: "claude-3")],
            costPriority: 0.3,           // Prefer cheaper models (0-1)
            speedPriority: 0.5,          // Balance speed (0-1)
            intelligencePriority: 0.8    // Prefer capable models (0-1)
        ),
        systemPrompt: "You are a helpful translator.",
        maxTokens: 200,
        temperature: 0.3,
        stopSequences: ["---"]
    )
)
```

### Parameters

- `messages`: Conversation history
- `systemPrompt`: System prompt for the model
- `maxTokens`: Maximum tokens in response
- `temperature`: Sampling temperature
- `modelPreferences`: Model selection hints
- `stopSequences`: Sequences that stop generation
- `includeContext`: Whether to include conversation context

## Multi-turn Conversations

Build a conversation with multiple messages:

```swift
let result = try await server.createMessage(
    CreateSamplingMessage.Parameters(
        messages: [
            .user(.text("What is 2 + 2?")),
            .assistant(.text("2 + 2 equals 4.")),
            .user(.text("And if I add 3 more?"))
        ],
        maxTokens: 100
    )
)
```

## Sampling with Tools

Request completions that can use tools with ``Server/createMessageWithTools(_:)``:

```swift
let result = try await server.createMessageWithTools(
    CreateSamplingMessageWithTools.Parameters(
        messages: [.user(.text("What's the weather in Paris?"))],
        maxTokens: 500,
        tools: [
            Tool(
                name: "get_weather",
                description: "Get current weather",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "location": ["type": "string"]
                    ]
                ]
            )
        ],
        toolChoice: ToolChoice(mode: .auto)
    )
)

// Check if model wants to use a tool
for content in result.content {
    if case .toolUse(let toolUse) = content {
        print("Model wants to call: \(toolUse.name)")
        print("With arguments: \(toolUse.input)")
    }
}
```

## Handling Responses

### Basic Sampling Response

For `createMessage` (without tools), the response contains a single content block:

```swift
let result = try await server.createMessage(...)

// Content is a single block (text, image, or audio)
switch result.content {
    case .text(let text, _, _):
        print("Text: \(text)")
    case .image(let data, let mimeType, _, _):
        print("Image: \(mimeType)")
    case .audio(let data, let mimeType, _, _):
        print("Audio: \(mimeType)")
}

// Check stop reason
switch result.stopReason {
    case .endTurn:
        print("Natural end of response")
    case .maxTokens:
        print("Hit token limit")
    default:
        break
}
```

### Sampling with Tools Response

For `createMessageWithTools`, the response contains an array of content blocks (to support parallel tool calls):

```swift
let result = try await server.createMessageWithTools(...)

// Content is an array of blocks
for content in result.content {
    switch content {
        case .text(let text, _, _):
            print("Text: \(text)")
        case .toolUse(let toolUse):
            print("Tool call: \(toolUse.name)")
            print("Arguments: \(toolUse.input)")
        default:
            break
    }
}

// Check stop reason
switch result.stopReason {
    case .endTurn:
        print("Natural end of response")
    case .maxTokens:
        print("Hit token limit")
    case .toolUse:
        print("Stopped for tool use")
    default:
        break
}
```

## Error Handling

Handle cases where sampling isn't available:

```swift
do {
    let result = try await server.createMessage(...)
} catch let error as MCPError {
    if case .invalidRequest(let message) = error,
       message.contains("sampling") {
        // Client doesn't support sampling
        return CallTool.Result(
            content: [.text("This feature requires an AI-capable client")],
            isError: true
        )
    }
    throw error
}
```

## See Also

- <doc:server-setup>
- <doc:client-sampling>
- ``Server``

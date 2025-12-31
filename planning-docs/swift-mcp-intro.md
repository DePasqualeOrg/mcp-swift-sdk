# Swift MCP Intro

## Possible Configurations

- Client only

  - Give a model access to tools from a third-party MCP server (local or remote)
    - Chat interaction
    - Intelligent features 

- Server only

  - Expose generic tools, resources, etc. to remote clients
    - Ideal if you prefer to use Swift also on the server
    - Can run on Apple platforms and Linux
  - Expose Apple-native tools on a Mac for use on a local network or through a VPN (e.g. Tailscale)

- Client + server in same process

  - Expose Apple-native tools to an app on any Apple device, including iOS

    - HTTP and stdio don't work on iOS, but the client and server can run within the same app.
    - Can also be more convenient in a sandboxed Mac environment

    

- Examples of Apple-native tools
  - Contacts
  - Calendar
  - Reminders
  - Health
  - UI automation (Accessibility)
  - Messages
  - ... any Apple SDK

## Example Use Cases

### Client Only

Your Swift app connects to external MCP servers to extend what a model can do.

**Mac apps (connecting to local MCP servers):**

- A chat app that connects to filesystem, git, and database servers
  - Build your own Claude Desktop-like experience

- A coding assistant that uses servers for code search, linting, or documentation lookup
- An internal tool that connects to your company's MCP servers for querying internal systems

**Any platform (connecting to remote MCP servers):**

- An app that connects to a web search server for grounded responses
- Integration with cloud services exposed via MCP (Slack, GitHub, Linear, etc.)
- Connecting to a hosted RAG server for domain-specific knowledge

### Server Only

You build an MCP server in Swift that other clients connect to.

**Cross-platform Swift servers (Apple + Linux):**

- Wrap your company's REST APIs as MCP tools so any MCP client can use them
- Expose an MLX or CoreML model as a tool (image classification, text embedding, etc.)

**Mac as a bridge to the Apple ecosystem:**

- A Mac mini running an MCP server that exposes smart home controls (HomeKit)
- Expose your media library (Music, Photos, TV) for AI-powered organization or recommendations
- A server that can trigger Shortcuts, enabling complex automations from any MCP client
- Expose Finder/filesystem operations for a remote AI assistant

### Client + Server in Same Process

Both run inside your app – the only viable pattern for server capabilities on iOS.

**Personal productivity (iOS/Mac):**

- An assistant that can read/write Contacts, Calendar events, and Reminders
  - "Schedule lunch with Sarah next week" actually works

- A journaling app where the model can reference past entries to provide reflections
- A task manager where the model can reorganize your to-dos, set due dates, suggest priorities

**Health and wellness:**

- An app that analyzes your HealthKit data (sleep, activity, heart rate) and provides insights
- A fitness coach that can see your workout history and create personalized plans
- Mood tracking app where the AI correlates entries with health metrics

**Communication:**

- Draft and send Messages through an AI interface
- An email client where the model can search, summarize, and draft replies
- A social media manager that can post across platforms

**Creative/media:**

- Photo organizer that uses Vision to tag, search, and curate your library
- Music app that analyzes your listening history and creates playlists
- Note-taking app where the AI can search and synthesize across all your notes

**Accessibility and automation:**

- An AI that can control your device via Accessibility APIs - "open Settings and turn on Do Not Disturb"
- Voice-controlled Mac automation for users with motor impairments
- A "computer use" style agent that operates entirely on-device

**Developer tools:**

- An iOS app for reviewing PRs on the go, with tools for fetching diffs and leaving comments
- A Swift Playgrounds-style app where the AI can execute code and see results

## Integration Work

What app developers need to do beyond importing the SDK.

### Client Integration

1. Create and configure the client
   - Initialize with app name and version
   - Declare capabilities before connecting (sampling, roots, etc.)

2. Choose a transport
   - **InMemoryTransport** – Same-process client+server (iOS, sandboxed Mac)
   - **StdioTransport** – Local CLI tools (how Claude Desktop works)
   - **HTTPClientTransport** – Remote servers

3. Connect and discover capabilities
   - Connect to the server via chosen transport
   - List available tools, resources, prompts

### Server Integration

1. Define tools
   - Use the `@Tool` macro for declarative tool definitions
   - Add `@Parameter` for each input with descriptions
   - Implement `perform()` to execute the tool's logic
   - The macro auto-generates JSON Schema from Swift types

2. Register and start the server
   - Register tool types with the server
   - Choose transport: stdio for CLI tools, in-memory for same-process

### In-Process Setup (iOS Pattern)

- Create paired transports using `InMemoryTransport.createConnectedPair()`
- Start server on one side, connect client on the other
- Works within iOS sandbox where HTTP/stdio aren't viable
- Also useful for sandboxed Mac apps

### Bridging MCP to LLM APIs

MCP tools need to be converted to whatever format your LLM expects.

**Outbound (MCP → LLM):**
- Get tools from MCP client
- Convert to Anthropic/OpenAI tool format
- The `inputSchema` is already JSON Schema – pass it through

**Inbound (LLM → MCP → LLM):**
- Parse tool_use blocks from LLM response
- Call MCP tool with name and arguments
- Convert MCP result content (text, images, etc.) back to LLM format
- Send as tool_result in next LLM request

### The Agentic Loop

The core control flow that enables multi-step tool use.

**Basic flow:**

```
User message
     ↓
┌─→ LLM API call (with tools)
│        ↓
│   Response contains tool_use?
│      ↓           ↓
│     Yes          No → Return final text to user
│      ↓
│   Execute tools via MCP
│      ↓
│   Add results to conversation
│      ↓
└──────┘
```

**Key points:**
- Loop continues until model stops requesting tools (stop_reason != tool_use)
- Each iteration: call LLM → check for tool use → execute → feed results back
- Conversation history grows with assistant messages and tool results

**Termination conditions:**
- **Model signals done** – stop_reason is end_turn or stop_sequence (the happy path)
- **Max iterations** – Hard cap on loop turns (e.g., 10-25 iterations)
- **Token budget** – Cumulative input/output tokens exceed a limit
- **Timeout** – Wall-clock time limit for the entire loop
- **User cancellation** – User aborts mid-execution
- **Error threshold** – Too many consecutive tool failures

Without these safeguards, a misbehaving model could loop indefinitely or run up costs.

**Production considerations:**

- **User confirmation** – Show pending tool calls, require approval for sensitive actions
- **Parallel execution** – Multiple tool calls can run concurrently when independent
- **Streaming** – Stream text to UI while accumulating tool calls for better UX
- **Error handling** – Gracefully handle tool failures, surface errors to the model

### Sampling (Server-Initiated LLM Calls)

Allows servers to request LLM completions through the client.

**How it works:**
- Client registers a sampling handler that calls an LLM service
- Server tools can call `context.createMessage()` to get completions
- Enables "agentic tools" that can think/reason during execution

**Use cases:**
- Tool that needs to analyze or summarize data before acting
- Multi-step reasoning within a single tool call
- Delegating sub-tasks to the model

### User Consent and Confirmation

MCP spec emphasizes user control – this is app-level responsibility.

**What to implement:**
- Show tool calls before execution (name, arguments)
- Require confirmation for sensitive actions (send, delete, purchase)
- Display results for user review
- Allow users to deny/cancel tool execution

**Design decisions:**
- Which tools require confirmation?
- How to present tool arguments readably?
- What happens when user denies permission?

### Lifecycle Management

**Connection lifecycle:**
- SDK handles initialize/initialized handshake automatically
- Declare capabilities before connecting
- Handle disconnections – reconnect or surface error to user

**Tool execution lifecycle:**
- Long-running tools can report progress
- Support cancellation via context
- Clean up resources on termination


# Getting Started

## Overview

The simplest way to get started is connecting a client and server within the same process using ``InMemoryTransport``.

For other transports like stdio and HTTP, see the <doc:client-guide> and <doc:server-guide>.

## Example

```swift
import MCP
import MCPTool

// Define a tool
@Tool
struct Greet {
    static let name = "greet"
    static let description = "Greet someone by name"

    @Parameter(description: "Name to greet")
    var name: String

    func perform() async throws -> String {
        "Hello, \(name)!"
    }
}

// Create the server
let server = MCPServer(name: "MyServer", version: "1.0.0")

// Register tools
try await server.register {
    Greet.self
}

// Create the client
let client = Client(name: "MyApp", version: "1.0.0")

// Create the transports
let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

// Start the server and connect the client
try await server.connect(transport: serverTransport)
try await client.connect(transport: clientTransport)

// Use the client to interact with the server
let tools = try await client.listTools()
print("Available tools: \(tools.tools.map { $0.name })")

let result = try await client.callTool(name: "greet", arguments: ["name": "MCP"])
if case .text(let text, _, _) = result.content.first {
    print(text)  // "Hello, MCP!"
}

// Clean up
await client.disconnect()
await server.close()
```

## How It Works

1. **Define tools with `@Tool`**: Import `MCPTool` to access the `@Tool` macro and `@Parameter` property wrapper. The macro generates JSON Schema from your Swift types and handles argument parsing automatically.

2. **Create an ``MCPServer``**: The high-level server manages capabilities and request handlers for you.

3. **Register tools**: Use the result builder syntax to register one or more tools.

4. **Connect via transport**: Both client and server connect through a shared transport (in-memory, stdio, or HTTP).

## Next Steps

- <doc:client-guide>: Build MCP clients
- <doc:server-guide>: Build MCP servers
- <doc:transports>: Available transport options

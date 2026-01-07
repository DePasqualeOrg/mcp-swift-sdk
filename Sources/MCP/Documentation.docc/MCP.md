# ``MCP``

Swift SDK for the Model Context Protocol (MCP).

## Overview

The Model Context Protocol defines a standardized way for applications to communicate with AI and ML models. This Swift SDK implements both client and server components according to the [2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/) version of the MCP specification.

Use the SDK to:
- **Build MCP clients** that connect to servers and access tools, resources, and prompts
- **Build MCP servers** that expose capabilities to AI applications
- **Choose from multiple transports** including stdio, HTTP, and custom implementations

## Requirements

- Swift 6.0+ (Xcode 16+)
- See <doc:GettingStarted> for platform-specific requirements

## Topics

### Guides

- <doc:GettingStarted>
- <doc:ClientGuide>
- <doc:ServerGuide>
- <doc:Transports>
- <doc:Examples>
- <doc:Debugging>
- <doc:Experimental>

### Core

- ``Client``
- ``Server``

### Transports

- ``Transport``
- ``StdioTransport``
- ``HTTPClientTransport``
- ``HTTPServerTransport``
- ``InMemoryTransport``
- ``NetworkTransport``

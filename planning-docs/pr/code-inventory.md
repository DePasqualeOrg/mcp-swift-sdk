# PR #175 Source File Inventory

Comparison of source files between **main** branch (before PR) and **PR branch** (2025-11-25).

## Files Split Into Extensions

### Client

| Original (main) | PR Branch | Lines (main → PR) |
|-----------------|-----------|-------------------|
| `Client/Client.swift` | `Client/Client.swift` | 753 → 859 |
| | `Client/Client+Batching.swift` | (new) 164 |
| | `Client/Client+MessageHandling.swift` | (new) 486 |
| | `Client/Client+ProtocolMethods.swift` | (new) 166 |
| | `Client/Client+Registration.swift` | (new) 264 |
| | `Client/Client+Requests.swift` | (new) 526 |
| | `Client/Client+Tasks.swift` | (new) 256 |
| **Total Client** | | **753 → 2,721** |

### Server

| Original (main) | PR Branch | Lines (main → PR) |
|-----------------|-----------|-------------------|
| `Server/Server.swift` | `Server/Server.swift` | 652 → 1,235 |
| | `Server/Server+ClientRequests.swift` | (new) 370 |
| | `Server/Server+RequestHandling.swift` | (new) 501 |
| | `Server/Server+Sending.swift` | (new) 66 |
| **Total Server** | | **652 → 2,172** |

## Modified Files (Significantly Expanded)

| File | Lines (main → PR) | Notes |
|------|-------------------|-------|
| `Base/Error.swift` | 245 → 455 | Enhanced error types |
| `Base/Lifecycle.swift` | ~80 → 82 | Minor additions |
| `Base/Messages.swift` | ~150 → 154 | Additional message types |
| `Base/Versioning.swift` | ~30 → 32 | Updated protocol versions |
| `Base/Transport.swift` | 20 → 195 | Added per-message context, session info |
| `Base/Transports/HTTPClientTransport.swift` | 566 → 1,044 | Streamable HTTP, resumability |
| `Base/Transports/NetworkTransport.swift` | 848 → 738 | Refactored (bug fixes) |
| `Client/Sampling.swift` | 238 → 781 | Tools, toolChoice, enhanced models |
| `Server/Tools.swift` | 262 → 467 | outputSchema, structuredContent, icons, titles |
| `Server/Resources.swift` | 212 → 515 | ResourceLink, icons, titles |
| `Server/Prompts.swift` | 260 → 414 | Icons, titles |

## New Files in PR

### Base Layer

| File | Lines | Purpose |
|------|-------|---------|
| `Base/Annotations.swift` | 40 | Content annotations |
| `Base/HTTPHeader.swift` | 45 | HTTP header constants |
| `Base/Icon.swift` | 51 | Icon metadata type |
| `Base/Progress.swift` | 324 | Progress tracking notifications |
| `Base/RequestId.swift` | 10 | Request ID type (split from ID.swift) |
| `Base/Transports/HTTPClientTransport+Types.swift` | 42 | HTTP client configuration types |
| `Base/Transports/HTTPServerTransport+Types.swift` | 444 | Session manager protocol, event store |
| `Base/Transports/HTTPServerTransport.swift` | 1,197 | Streamable HTTP server transport |
| `Base/Transports/InMemoryEventStore.swift` | 279 | Event storage for resumability |
| `Base/Transports/OAuth.swift` | 126 | OAuth foundation |
| `Base/Utilities/ExtraFieldsCoding.swift` | 112 | Extra fields coding for extensibility |

### Client Layer

| File | Lines | Purpose |
|------|-------|---------|
| `Client/Elicitation.swift` | 789 | Elicitation (form mode + URL mode) |
| `Client/Roots.swift` | 135 | Roots capability |
| `Client/Experimental/ExperimentalClientFeatures.swift` | 330 | Experimental feature flags |
| `Client/Experimental/Tasks/ClientTaskSupport.swift` | 231 | Client-side task support |

### Server Layer

| File | Lines | Purpose |
|------|-------|---------|
| `Server/Completions.swift` | 338 | Autocomplete suggestions |
| `Server/Logging.swift` | 100 | MCP protocol logging |
| `Server/SessionManager.swift` | 225 | Multi-session management |
| `Server/ToolNameValidation.swift` | 111 | Tool name spec validation |
| `Server/Experimental/ExperimentalServerFeatures.swift` | 217 | Experimental server features |
| `Server/Experimental/Tasks/ServerTaskContext.swift` | 959 | Server task execution context |
| `Server/Experimental/Tasks/TaskContext.swift` | 282 | Task context abstraction |
| `Server/Experimental/Tasks/TaskMessageQueue.swift` | 416 | Task message queuing |
| `Server/Experimental/Tasks/TaskResultHandler.swift` | 136 | Task result handling |
| `Server/Experimental/Tasks/TaskStore.swift` | 335 | Task storage |
| `Server/Experimental/Tasks/TaskSupport.swift` | 286 | Task support types |
| `Server/Experimental/Tasks/Tasks.swift` | 1,013 | Task types and protocol |

## Unchanged Files

| File | Notes |
|------|-------|
| `Base/ID.swift` | Exists on main (RequestId split out) |
| `Base/UnitInterval.swift` | Unchanged |
| `Base/Value.swift` | Unchanged |
| `Base/Transports/InMemoryTransport.swift` | Minor changes |
| `Base/Transports/StdioTransport.swift` | Minor changes |
| `Base/Utilities/Ping.swift` | Unchanged |
| `Extensions/Data+Extensions.swift` | Unchanged |

## Summary

| Category | main | PR Branch |
|----------|------|-----------|
| Source files | 20 | 54 |
| New files | - | 34 |
| Lines of code (approx.) | ~5,400 | ~17,500+ |

## Features Added

- **HTTP server transport**: `HTTPServerTransport` for Streamable HTTP (2025-03-26+)
- **Session management**: `SessionManager` for multi-client sessions
- **Event storage**: `InMemoryEventStore` for session resumability
- **Tasks (experimental)**: Long-running operations with polling model
- **Elicitation**: Form mode and URL mode for structured user input
- **Completions**: Autocomplete suggestions for arguments
- **Progress**: Progress tracking notifications
- **Roots**: Client root directory exposure
- **Logging**: MCP protocol logging from servers
- **Icons**: Icon metadata on tools, resources, prompts, templates
- **Titles**: Title fields on tools, prompts, resources, templates
- **Structured tool output**: `outputSchema` and `structuredContent`
- **Resource links**: `ResourceLink` content type in tool results
- **Tool name validation**: Warns on invalid tool names per spec

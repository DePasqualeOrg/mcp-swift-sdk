# Phased Review

## Strategy

### Initial Merge

Merge all changes to upstream in a single PR with two levels of review:

1. **Full review**: Modified existing functionality (bug fixes, security, spec compliance)
2. **Sanity check**: New functionality (mark as experimental in documentation)

No code restructuring needed. Experimental status communicated via documentation only.

### Post-Merge: Progressive Stabilization

After the initial merge, each experimental feature group can be fully reviewed and graduated to stable status:

| Review Phase | Features | After Review |
|--------------|----------|--------------|
| A | HTTP Server Transport | Mark stable |
| B | Batching, Annotations, Progress | Mark stable |
| C | Elicitation, Completions | Mark stable |
| D | Structured Output, Resource Links, Icons | Mark stable |
| E | Sampling Tools, Roots, Logging | Mark stable |
| F | Tasks | Still experimental per MCP spec |
| G | Tool and Prompt Macros | Mark stable |

Each phase:
1. Full review of the feature code
2. Verify test coverage is adequate
3. Update documentation to remove experimental notice

Features can be reviewed in any order based on priority and community demand.

---

## Summary

| Review Level | Description | Lines | Files |
|--------------|-------------|-------|-------|
| **Full Review** | Bug fixes, security, spec compliance, infrastructure | ~2,500 | ~15 |
| **Sanity Check** | New features (experimental) | ~15,400 | ~57 |
| **Total** | | **~17,900** | **72** |

---

## Part 1: Full Review (~2,500 lines, ~15 files)

These changes modify existing behavior and must be carefully reviewed.

### 1.1 Critical Bug Fixes

| File | Bug | Reference |
|------|-----|-----------|
| `Client/Client.swift` | Receive loop re-consuming AsyncThrowingStream | PR #170 |
| `Client/Client.swift` | Receive loop spinning at 100% CPU after transport closes | PR #171 |
| `Base/Transports/NetworkTransport.swift` | Crash on reconnect (continuation resumed multiple times) | Issue #137 |
| `Base/Transports/InMemoryTransport.swift` | Race condition with message queue | - |
| `Base/Transports/StdioTransport.swift` | CRLF line ending handling | - |
| `Base/Error.swift` | Equality was code-only, encoding used errorDescription | - |

### 1.2 Security Fixes

| File | Issue |
|------|-------|
| `Server/Server.swift` | Information disclosure via `error.localizedDescription` |
| `Base/Messages.swift` | Same security fix for client-side request handling |

### 1.3 Spec Compliance Fixes (2025-03-26)

| File | Fix | Spec Reference |
|------|-----|----------------|
| `Base/Transports/HTTPClientTransport.swift` | Content-Type validation only for requests | transports.mdx L105-108 |
| `Base/Transports/HTTPClientTransport.swift` | Notification response must be 202 Accepted | transports.mdx L98-101 |
| `Server/Tools.swift` | EmbeddedResource structure fix | schema.ts L654-662 |
| `Server/Prompts.swift` | Same EmbeddedResource fix | schema.ts L654-662 |
| `Base/Error.swift` | `ErrorCode.resourceNotFound = -32002` | resources.mdx L335 |

### 1.4 Infrastructure Changes (Required for New Features)

| File | Lines | Change |
|------|-------|--------|
| `Base/Transport.swift` | 20 → 209 | `TransportMessage`, `MessageContext`, session support |
| `Base/HTTPHeader.swift` | 45 (new) | HTTP header constants |
| `Base/RequestId.swift` | 73 | Renamed from `ID.swift` with deprecation alias |
| `Base/Versioning.swift` | 28 → 54 | Version constants, `defaultNegotiated` |

**Key change in Transport.swift:**

```swift
// Old
func receive() -> AsyncThrowingStream<Data, Swift.Error>

// New
func receive() -> AsyncThrowingStream<TransportMessage, Swift.Error>
```

### 1.5 Code Quality Improvements

| File | Improvement |
|------|-------------|
| `Base/Messages.swift` | Removed force casts (`as!`) - use safe conditional casts |
| `Client/Sampling.swift` | `StopReason` as `RawRepresentable` struct |
| `Server/Tools.swift` | Convenience initializers for content types |
| `Server/Prompts.swift` | Same convenience initializers |
| `Base/Error.swift` | Centralized `ErrorCode` enum |
| `Base/Transports/*.swift` | `AsyncThrowingStream.makeStream()` pattern |
| `Base/Transports/NetworkTransport.swift` | Simplified completion handlers |
| `Base/Transports/HTTPClientTransport.swift` | Session ID signal using AsyncStream |

### 1.6 Files Requiring Full Review

| File | Lines (old → new) | Key Changes |
|------|-------------------|-------------|
| `Base/Transport.swift` | 20 → 209 | Protocol signature change, new types |
| `Base/Error.swift` | 245 → 639 | Bug fixes, ErrorCode enum |
| `Base/Messages.swift` | 398 → 522 | Security fix, safe decoding |
| `Base/Transports/HTTPClientTransport.swift` | 566 → 1,044 | Spec fixes, session handling |
| `Base/Transports/NetworkTransport.swift` | 848 → 738 | Crash fix, refactored |
| `Base/Transports/StdioTransport.swift` | 235 → 248 | CRLF fix |
| `Base/Transports/InMemoryTransport.swift` | 197 → 181 | Race condition fix |
| `Client/Client.swift` | 753 → 871 | Receive loop fixes |
| `Server/Server.swift` | 652 → 1,298 | Security fix |
| `Server/Tools.swift` | 262 → 466 | EmbeddedResource fix + new features |
| `Server/Prompts.swift` | 260 → 414 | EmbeddedResource fix + new features |

---

## Part 2: Sanity Check - Experimental Features (~15,400 lines, ~57 files)

New functionality implementing spec versions 2025-03-26 through 2025-11-25. Review for obvious issues only. Mark as experimental in documentation.

### 2.1 HTTP Server Transport (2025-03-26)

| File | Lines | Purpose |
|------|-------|---------|
| `Base/Transports/HTTPServerTransport.swift` | 1,202 | Streamable HTTP server |
| `Base/Transports/HTTPServerTransport+Types.swift` | 524 | Configuration, session manager protocol |
| `Base/Transports/InMemoryEventStore.swift` | 279 | Event storage for resumability |
| `Server/SessionManager.swift` | 225 | Multi-session management protocol |
| `Server/BasicHTTPSessionManager.swift` | 258 | Basic session manager implementation |

**Spec**: PR [#206](https://github.com/modelcontextprotocol/specification/pull/206)

### 2.2 JSON-RPC Batching (2025-03-26)

| File | Lines | Purpose |
|------|-------|---------|
| `Client/Client+Batching.swift` | 164 | Batch request support |

**Spec**: PR [#228](https://github.com/modelcontextprotocol/specification/pull/228)

### 2.3 Content Annotations & Progress (2025-03-26)

| File | Lines | Purpose |
|------|-------|---------|
| `Base/Annotations.swift` | 40 | `ContentAnnotations`, top-level `Role` |
| `Base/Progress.swift` | 324 | `RequestMeta`, `ProgressToken`, `ProgressNotification` |
| `Base/Utilities/ExtraFieldsCoding.swift` | 112 | `_meta` field support |

### 2.4 Elicitation (2025-06-18)

| File | Lines | Purpose |
|------|-------|---------|
| `Client/Elicitation.swift` | 818 | Form mode and URL mode elicitation |

**Spec**: PR [#382](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/382)

### 2.5 Completions (2025-06-18)

| File | Lines | Purpose |
|------|-------|---------|
| `Server/Completions.swift` | 338 | Autocomplete for prompts/resources |

**Spec**: PR [#598](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/598)

### 2.6 Structured Output, Resource Links, Icons, Titles (2025-06-18)

| File | Lines | Purpose |
|------|-------|---------|
| `Base/Icon.swift` | 51 | Icon type with theme support |
| `Base/JSONSchemaValidator.swift` | 133 | Schema validation utilities |
| `Server/Resources.swift` | 212 → 515 | `ResourceLink`, icons, titles |

Changes in `Tools.swift`, `Prompts.swift`, `Resources.swift`:
- `outputSchema` and `structuredContent` on tools
- `ResourceLink` content type
- `icons` and `title` fields

**Spec**: PRs [#371](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/371), [#603](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/603), [#663](https://github.com/modelcontextprotocol/modelcontextprotocol/pull/663)

### 2.7 Sampling with Tools (2025-11-25)

| File | Lines | Purpose |
|------|-------|---------|
| `Client/Sampling.swift` | 238 → 781 | `tools`, `toolChoice`, `ToolDefinition`, `ToolChoice` |

**Spec**: SEP-1577

### 2.8 Client Roots (2025-11-25)

| File | Lines | Purpose |
|------|-------|---------|
| `Client/Roots.swift` | 135 | Expose filesystem scope to servers |

### 2.9 Logging & Tool Validation (2025-11-25)

| File | Lines | Purpose |
|------|-------|---------|
| `Server/Logging.swift` | 100 | Server-to-client logging |
| `Server/ToolNameValidation.swift` | 109 | Tool name validation per spec |

### 2.10 Experimental Tasks (2025-11-25)

Already marked experimental in the MCP spec itself.

| File | Lines | Purpose |
|------|-------|---------|
| `Server/Experimental/Tasks/Tasks.swift` | 1,013 | Core task types |
| `Server/Experimental/Tasks/ServerTaskContext.swift` | 972 | Task execution environment |
| `Server/Experimental/Tasks/TaskContext.swift` | 282 | Context abstraction |
| `Server/Experimental/Tasks/TaskStore.swift` | 335 | Task persistence |
| `Server/Experimental/Tasks/TaskMessageQueue.swift` | 416 | Message queuing |
| `Server/Experimental/Tasks/TaskResultHandler.swift` | 136 | Result routing |
| `Server/Experimental/Tasks/TaskSupport.swift` | 286 | Configuration |
| `Server/Experimental/ExperimentalServerFeatures.swift` | 217 | Server feature flags |
| `Client/Experimental/Tasks/ClientTaskSupport.swift` | 231 | Client task support |
| `Client/Experimental/ExperimentalClientFeatures.swift` | 330 | Client feature flags |
| `Client/Client+Tasks.swift` | 256 | Task polling methods |

**Spec**: SEP-1686

### 2.11 Tool DSL (~1,579 lines)

| File | Lines | Purpose |
|------|-------|---------|
| `ToolDSL/ToolSpec.swift` | 147 | Tool specification |
| `ToolDSL/ToolRegistry.swift` | 332 | Registration and lookup |
| `ToolDSL/RegisteredTool.swift` | 64 | Registered tool wrapper |
| `ToolDSL/Parameter.swift` | 469 | Parameter definitions |
| `ToolDSL/ToolContext.swift` | 262 | Execution context |
| `ToolDSL/ToolOutput.swift` | 233 | Output types |
| `ToolDSL/AnnotationOption.swift` | 72 | Annotation config |

### 2.12 Prompt DSL (~340 lines)

| File | Lines | Purpose |
|------|-------|---------|
| `PromptDSL/PromptSpec.swift` | 148 | Prompt specification |
| `PromptDSL/PromptBuilder.swift` | 40 | Building utilities |
| `PromptDSL/Argument.swift` | 152 | Argument definitions |

### 2.13 Swift Macros (~1,468 lines)

| File | Lines | Purpose |
|------|-------|---------|
| `MCPMacros/MCPMacrosPlugin.swift` | 11 | Plugin registration |
| `MCPMacros/ToolMacro.swift` | 852 | `@Tool` macro |
| `MCPMacros/PromptMacro.swift` | 409 | `@Prompt` macro |
| `MCPMacros/OutputSchemaMacro.swift` | 196 | `@OutputSchema` macro |

### 2.14 High-Level Wrappers & Registries

| File | Lines | Purpose |
|------|-------|---------|
| `Server/MCPServer.swift` | 747 | Convenience server wrapper |
| `Server/ResourceRegistry.swift` | 700 | Resource indexing |
| `Server/PromptRegistry.swift` | 280 | Prompt indexing |

### 2.15 Refactored Extensions

Code extracted from `Client.swift` and `Server.swift` for maintainability:

| File | Lines | Content |
|------|-------|---------|
| `Client/Client+MessageHandling.swift` | 486 | Message routing |
| `Client/Client+ProtocolMethods.swift` | 198 | Protocol implementations |
| `Client/Client+Registration.swift` | 269 | Capability registration |
| `Client/Client+Requests.swift` | 526 | Request sending |
| `Server/Server+ClientRequests.swift` | 426 | Client request handling |
| `Server/Server+HighLevelAPI.swift` | 33 | Convenience methods |
| `Server/Server+RequestHandling.swift` | 509 | Request dispatch |
| `Server/Server+Sending.swift` | 66 | Message sending |

---

## Documentation Requirements

### Experimental Features Notice

Add to README and documentation:

> **Experimental Features**
>
> This SDK implements MCP specification versions through 2025-11-25. Features from spec versions 2025-03-26 and later are considered experimental and may change in future releases:
>
> - HTTP Server Transport
> - JSON-RPC Batching
> - Content Annotations & Progress Notifications
> - Elicitation (Form and URL modes)
> - Completions
> - Structured Tool Output
> - Resource Links
> - Icons and Titles
> - Sampling with Tools
> - Client Roots
> - Protocol Logging
> - Tasks (also experimental in MCP spec)
> - `@Tool` macro
> - `@Prompt` macro

### Per-Feature Documentation

Each experimental feature should have a doc comment noting its status:

```swift
/// Creates an elicitation request to gather structured user input.
///
/// - Important: Experimental API (MCP 2025-06-18). May change in future releases.
public func elicit(...) { }
```

---

## Spec Version Reference

| Version | Features | Status |
|---------|----------|--------|
| **2024-11-05** | Tools, resources, prompts, stdio | Stable |
| **2025-03-26** | HTTP transport, batching, annotations, progress | Experimental |
| **2025-06-18** | Elicitation, completions, structured output, resource links | Experimental |
| **2025-11-25** | Tasks, sampling tools, roots, logging, tool validation | Experimental |

---

## Review Checklist

### Part 1: Full Review

For each file:
- [ ] Bug fix is correct and complete
- [ ] No regressions to existing behavior
- [ ] Security issues properly addressed
- [ ] Spec compliance verified against spec docs
- [ ] Error handling is appropriate
- [ ] Concurrency is safe (no data races)
- [ ] Tests cover the changes

### Part 2: Sanity Check

For each feature:
- [ ] Code compiles and basic functionality works
- [ ] No obvious security issues
- [ ] No egregious design problems
- [ ] Documentation notes experimental status
- [ ] Tests exist (don't need to be exhaustive)

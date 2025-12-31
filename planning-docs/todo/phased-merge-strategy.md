# Phased Merge Strategy

This document describes the strategy for merging changes from the fork into the upstream repository using **stacked PRs**.

## Overview

The monolithic branch will be split into 8 stacked PRs, each building on the previous. This allows:
- All phases visible and reviewable simultaneously
- Parallel review by different reviewers
- Clear phase boundaries
- Automatic change propagation (using jj or Graphite)

## Phase Structure

```
main
 └─ PR0: Foundation (Transport.swift, HTTPHeader, RequestId, Error fixes)
     └─ PR1: Bug Fixes (receive loop, transport crashes, security fixes)
         └─ PR2: HTTP Server (HTTPServerTransport, OAuth, SessionManager)
             └─ PR3: Tool Infrastructure (Annotations, Progress, Icon, Elicitation, Logging, Sampling, Tools.swift)
                 └─ PR4: Tool DSL & Macros (experimental)
                     └─ PR5: Remaining Spec Features (Completions, Prompts, Resources, Roots)
                         └─ PR6: PromptDSL & High-Level APIs (MCPServer)
                             └─ PR7: Experimental Tasks (likely to change)
```

Each branch contains all changes from branches below it, plus its own changes.
Each PR shows only its own changes (diff against parent branch).

**Build requirement:** Each PR must compile independently (with all previous PRs merged). The phase ordering ensures all dependencies are satisfied.

### Line Counts

| PR | Description | Lines |
|----|-------------|------:|
| PR0 | Foundation | 1,701 |
| PR1 | Bug Fixes | 4,902 |
| PR2 | HTTP Server | 2,656 |
| PR3 | Tool Infrastructure | 2,848 |
| PR4 | Tool DSL & Macros | 2,638 |
| PR5 | Remaining Spec Features | 1,675 |
| PR6 | PromptDSL & High-Level APIs | 4,989 |
| PR7 | Experimental Tasks | 4,474 |
| **Total** | | **25,883** |

Note: These are total file sizes. PR1 and PR6 include large files (`Client.swift`, `Server.swift`) where only portions are modified. Actual PR diffs will be smaller.

---

### PR0: Foundation (must go first)

All subsequent work depends on these changes.

```
Base/Transport.swift (full changes - TransportMessage, MessageContext, etc.)
Base/TransportType.swift (new)
Base/HTTPHeader.swift (new)
Base/RequestId.swift (rename from ID.swift)
Base/Value.swift (JSONSchema conversion additions)
Base/Versioning.swift (version constants, defaultNegotiated)
Base/Error.swift (bug fixes + ErrorCode enum)
Base/Utilities/Ping.swift (Parameters struct)
Base/Utilities/ExtraFieldsCoding.swift (new) - ResultWithExtraFields protocol
Extensions/Data+Extensions.swift (minor fix)
```

### PR1: Bug Fixes

Can be reviewed independently. Security-sensitive.

```
Client/Client.swift (receive loop fixes)
Base/Transports/NetworkTransport.swift (crash fix)
Base/Transports/InMemoryTransport.swift (race fix)
Base/Transports/StdioTransport.swift (CRLF fix)
Base/Transports/HTTPClientTransport.swift (spec compliance, session handling, reconnection)
Base/Messages.swift (security fix, safe decoding)
Server/Server.swift (security fix)
```

### PR2: HTTP Server

Isolated after Foundation. Includes OAuth support for HTTP transport.

```
Base/Transports/HTTPServerTransport.swift (new)
Base/Transports/HTTPServerTransport+Types.swift (new)
Base/Transports/HTTPClientTransport+Types.swift (new)
Base/Transports/OAuth.swift (new)
Base/Transports/InMemoryEventStore.swift (new)
Server/SessionManager.swift (new)
Server/BasicHTTPSessionManager.swift (new)
```

### PR3: Tool Infrastructure

Consolidates all Tool-related features to enable ToolDSL in PR4.

```
Base/Annotations.swift (new)
Base/Progress.swift (new)
Base/Icon.swift (new)
Base/JSONSchemaValidator.swift (new) - validates tool inputs/outputs
Client/Elicitation.swift (new) - provides ElicitationSchema, ElicitResult used by HandlerContext
Client/Sampling.swift (extensive modifications) - provides Sampling types used by HandlerContext
Server/Tools.swift (EmbeddedResource fix, annotations, outputSchema, structuredContent, icons, title)
Server/Logging.swift (new) - provides LoggingLevel used by HandlerContext
Client/Client.swift (add JSONSchemaValidator integration)
Server/Server.swift (add JSONSchemaValidator integration, elicitation methods)
Base/Lifecycle.swift (elicitation capability)
```

**Package.swift changes:** Add `swift-json-schema` dependency.

### PR4: Tool DSL & Macros (experimental)

The main draw for MCP server developers. Marked experimental until fully reviewed.
Users can always use the lower-level Tool API for stability.

```
ToolDSL/ToolSpec.swift (new)
ToolDSL/ToolRegistry.swift (new)
ToolDSL/ToolOutput.swift (new)
ToolDSL/ToolContext.swift (new) - defines HandlerContext
ToolDSL/Parameter.swift (new)
ToolDSL/AnnotationOption.swift (new)
ToolDSL/RegisteredTool.swift (new)
MCPMacros/ToolMacro.swift (new)
MCPMacros/OutputSchemaMacro.swift (new)
MCPMacros/MCPMacrosPlugin.swift (new) - macro plugin entry point
```

**Package.swift changes:** Add SwiftSyntax dependency for macros.

### PR5: Remaining Spec Features

```
Server/Completions.swift (new)
Client/Client+Batching.swift (new)
Server/Prompts.swift (EmbeddedResource fix, annotations, icons, title)
Server/Resources.swift (ResourceLink, icons, title)
Client/Roots.swift (new)
Server/ToolNameValidation.swift (new)
Base/Error.swift (urlElicitationRequired)
Base/Lifecycle.swift (completions, roots capabilities)
```

### PR6: PromptDSL & High-Level APIs

This PR includes code extraction refactoring. The `Client+*.swift` and `Server+*.swift` files are **new files** that extract code from the main `Client.swift` and `Server.swift` files.

```
PromptDSL/PromptSpec.swift (new)
PromptDSL/PromptBuilder.swift (new)
PromptDSL/Argument.swift (new)
MCPMacros/PromptMacro.swift (new)
Server/ResourceRegistry.swift (new)
Server/PromptRegistry.swift (new)
Server/MCPServer.swift (new) - high-level convenience API
Client/Client+MessageHandling.swift (new - extracted from Client.swift)
Client/Client+Requests.swift (new - extracted from Client.swift)
Client/Client+Registration.swift (new - extracted from Client.swift)
Client/Client+ProtocolMethods.swift (new - extracted from Client.swift)
Server/Server+Sending.swift (new - extracted from Server.swift)
Server/Server+RequestHandling.swift (new - extracted from Server.swift)
Server/Server+ClientRequests.swift (new - extracted from Server.swift)
Server/Server+HighLevelAPI.swift (new - extracted from Server.swift)
```

### PR7: Experimental Tasks (likely to change in next spec version)

```
Server/Experimental/ExperimentalServerFeatures.swift (new)
Server/Experimental/Tasks/Tasks.swift (new)
Server/Experimental/Tasks/TaskStore.swift (new)
Server/Experimental/Tasks/TaskContext.swift (new)
Server/Experimental/Tasks/ServerTaskContext.swift (new)
Server/Experimental/Tasks/TaskMessageQueue.swift (new)
Server/Experimental/Tasks/TaskResultHandler.swift (new)
Server/Experimental/Tasks/TaskSupport.swift (new)
Client/Experimental/ExperimentalClientFeatures.swift (new)
Client/Experimental/Tasks/ClientTaskSupport.swift (new)
Client/Client+Tasks.swift (new)
Base/Lifecycle.swift (tasks capability)
```

---

## Tooling

Managing a stacked PR workflow requires tooling for automatic rebase propagation.

| Tool | Cost | Change Propagation | Notes |
|------|------|-------------------|-------|
| **jj** | Free | Automatic | Git-compatible, maintainers don't need it |
| **Graphite** | $20/mo for org repos | Automatic | Web UI for stack visualization |
| **Plain git** | Free | Manual rebasing | Painful for deep stacks |

Both jj and Graphite work without requiring maintainers to change their workflow. They see normal GitHub PRs.

### Using jj

jj creates a `.jj/` directory alongside `.git/`. To start:

```bash
cd your-repo
jj git init --colocate
```

Maintainers and collaborators don't need jj - they just see normal git branches.

---

## Creating the Stack

### Recommended: Subtractive Approach (pare down from full)

Start with the full working branch and delete backwards. This is easier because:
- The full branch already compiles
- Deleting code surfaces missing dependencies immediately
- Each snapshot is a verified compilable state

```
Start: Full branch (everything, compiles)
       ↓ delete PR7 content, fix until compiles → snapshot
       ↓ delete PR6 content, fix until compiles → snapshot
       ...
       ↓ delete PR1 content, fix until compiles → snapshot
End:   PR0 only (minimal, compiles)
```

**With jj:**

```bash
# Start with full branch
jj new main -m "snapshot: full (PR7)"
# Copy everything from monolithic branch, verify it compiles

# Work backwards
jj new -m "snapshot: PR6 (minus Tasks)"
# Delete Server/Experimental/*, Client/Experimental/*, Client+Tasks.swift

jj new -m "snapshot: PR5 (minus PromptDSL and extensions)"
# Delete PromptDSL/*, MCPServer.swift, registries
# Merge Client+*.swift back into Client.swift
# Merge Server+*.swift back into Server.swift
# This step is more complex - see note below

# ... continue down to PR0
```

The actual stack is built from these snapshots:
```
PR0 = diff(main, pr0-snapshot)
PR1 = diff(pr0-snapshot, pr1-snapshot)
...
PR7 = diff(pr6-snapshot, pr7-snapshot)
```

### Note: PR6→PR5 Complexity

The PR6→PR5 step is more complex than other steps because:
- The `Client+*.swift` files extract ~500 lines from `Client.swift`
- The `Server+*.swift` files extract ~600 lines from `Server.swift`
- Going backwards requires merging this code back into the main files

To handle this:
1. Delete the extension files
2. Copy their contents back into the appropriate sections of `Client.swift` and `Server.swift`
3. Verify compilation

This is a one-time operation during stack creation. Once created, the stack is maintained normally.

---

## Ongoing Development

After creating the stack, develop at the top and move changes down as needed.

### Moving changes to a lower PR

```bash
# You added X to PR7, but it belongs in PR2
jj squash --from <pr7> --into <pr2>

# Stack auto-rebases - X propagates back up through PR3-PR7
```

### Editing a lower PR directly

```bash
jj edit <pr2>    # switch to PR2 commit
# make the change directly
jj new           # return to top; PR3-PR7 rebase automatically
```

**Key principle:** Changes propagate upward through rebasing. Edit a lower commit, and all descendants update automatically.

---

## Handling Review Feedback

When maintainers request changes to any PR:
1. Edit that commit (jj or Graphite handles this)
2. All PRs above it automatically rebase
3. Push updated stack

### If maintainers push directly to a PR branch

```bash
jj git fetch
# Descendants rebase automatically
```

---

## Division of Labor

```
PR0: Foundation      ← Maintainers review/edit (critical changes)
PR1: Bug Fixes       ← Maintainers review/edit (security-sensitive)
PR2: HTTP Server     ← Shared attention
PR3: Tool Infra      ← Shared attention (core feature)
PR4: Tool DSL        ← Contributor handles (experimental, convenience)
PR5: Spec Features   ← Contributor handles tweaks
PR6: PromptDSL       ← Contributor handles (convenience)
PR7: Tasks           ← Contributor handles (experimental, likely to change)
```

Maintainers focus on foundational PRs (0-3). Contributor handles convenience/experimental features (4-7).

---

## Merging

PRs merge bottom-up: PR0 first, then PR1, etc.

After PR0 merges into main, PR1's base automatically updates from the PR0 branch to main.

---

## Reference: File Dependencies

### Files with Cross-Phase Changes

These files accumulate changes across multiple phases. The stacked PR approach handles this naturally since each PR builds on the previous.

| File | Changes Across |
|------|----------------|
| `Transport.swift` | PR0 - all transports depend on it |
| `Value.swift` | PR0 (JSONSchema conversion additions) |
| `Versioning.swift` | PR0 (version constants) |
| `HTTPClientTransport.swift` | PR1 (spec compliance, session handling, reconnection) |
| `Client.swift` | PR1 (bug fixes), PR3 (validator), PR6 (code extracted to extensions) |
| `Server.swift` | PR1 (bug fixes), PR3 (validator, elicitation), PR6 (code extracted to extensions) |
| `Tools.swift` | PR3 (EmbeddedResource fix, annotations, outputSchema, structuredContent, icons, title) |
| `Prompts.swift` | PR5 (EmbeddedResource fix, annotations, icons, title) |
| `Resources.swift` | PR5 (ResourceLink, icons, title) |
| `Sampling.swift` | PR3 (extensive modifications - tools, toolChoice, used by HandlerContext) |
| `Lifecycle.swift` | PR0 (ResultWithExtraFields), PR3 (elicitation), PR5 (completions, roots), PR7 (tasks) |
| `Error.swift` | PR0 (fixes), PR5 (new error codes) |

### New Files (no conflicts)

These are completely new and have no conflicts with the original codebase:

**PR0:**
- `Base/TransportType.swift`, `HTTPHeader.swift`
- `Base/Utilities/ExtraFieldsCoding.swift`
- Note: `Versioning.swift`, `Value.swift`, `Error.swift`, `Ping.swift`, `Data+Extensions.swift` are modified, not new

**PR2:**
- `Base/Transports/HTTPServerTransport.swift`, `HTTPServerTransport+Types.swift`
- `Base/Transports/HTTPClientTransport+Types.swift`, `OAuth.swift`, `InMemoryEventStore.swift`
- `Server/SessionManager.swift`, `BasicHTTPSessionManager.swift`

**PR3:**
- `Base/Annotations.swift`, `Progress.swift`, `Icon.swift`, `JSONSchemaValidator.swift`
- `Client/Elicitation.swift`
- `Server/Logging.swift`

**PR4:**
- All `ToolDSL/*` files
- `MCPMacros/ToolMacro.swift`, `OutputSchemaMacro.swift`, `MCPMacrosPlugin.swift`

**PR5:**
- `Server/Completions.swift`, `ToolNameValidation.swift`
- `Client/Roots.swift`, `Client+Batching.swift`

**PR6:**
- All `PromptDSL/*` files
- `MCPMacros/PromptMacro.swift`
- `Server/ResourceRegistry.swift`, `PromptRegistry.swift`, `MCPServer.swift`
- `Client+*.swift` extensions (extracted from Client.swift)
- `Server+*.swift` extensions (extracted from Server.swift)

**PR7:**
- All `Server/Experimental/*` and `Client/Experimental/*` files
- `Client/Client+Tasks.swift`

### External Dependencies

| Feature | Dependency | Added In |
|---------|------------|----------|
| JSONSchemaValidator | `swift-json-schema` library | PR3 |
| MCPMacros | SwiftSyntax | PR4 |

### Documentation (out of scope)

The `Documentation.docc/` directory contains ~4,600 lines of new documentation. This is not included in the phased PRs above. Options:
- Include documentation with each PR that introduces the relevant feature
- Create a separate documentation PR
- Add documentation at the end

Decision: TBD

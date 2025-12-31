# Documentation Restructuring Plan

This document outlines the plan to restructure the MCP Swift SDK documentation from a single large README to a DocC-based documentation system hosted on Swift Package Index.

## Current State

The README is approximately 1000 lines and contains all documentation:
- Overview and installation
- Client usage (transports, tools, resources, prompts, sampling, error handling, advanced features)
- Server usage (tools, progress, resources, prompts, sampling, initialize hook, graceful shutdown)
- Transports
- Platform availability
- Debugging and logging

## Research Findings

### Swift Package Documentation Patterns

We analyzed documentation patterns across popular Swift packages:

| Package | README Lines | docs/ Folder | DocC | Documentation Strategy |
|---------|-------------|--------------|------|------------------------|
| mlx-swift | 173 | No | Via SPI | Nav bar links to SPI docs |
| mlx-swift-lm | 68 | No | Via SPI | Concise, links to SPI |
| swift-transformers | 172 | No | Via SPI | Badges link to SPI |
| WhisperKit | 332 | No | Via SPI | Separate BENCHMARKS.md |
| hummingbird | 105 | No | External | Links to docs.hummingbird.codes |
| **MCP Swift SDK** | **~1000** | **No** | **No** | **Everything in README** |

### Sibling MCP SDK Patterns

The TypeScript and Python SDKs use `docs/` folders:

**TypeScript SDK** (`docs/`):
- `capabilities.md`
- `client.md`
- `server.md`
- `faq.md`

**Python SDK** (`docs/`):
- `index.md`, `installation.md`, `concepts.md`
- `authorization.md`, `api.md`, `testing.md`
- `low-level-server.md`
- `experimental/` subfolder

### Key Observations

1. **Swift packages favor concise READMEs** (68-332 lines) - most are 5-10x shorter than the current MCP Swift SDK README

2. **API documentation via Swift Package Index** - Swift packages use `.spi.yml` with `documentation_targets` to auto-generate DocC from source code doc comments

3. **No docs/ folders in Swift ecosystem** - Unlike TypeScript/Python SDKs, Swift packages don't typically use a `docs/` folder

4. **Large projects link to external docs** - Projects prominently link to Swift Package Index or external documentation sites

### How Docstrings Integrate with DocC

Swift packages have two layers of documentation that work together:

| Layer | Source | Purpose |
|-------|--------|---------|
| **API Reference** | `///` docstrings in source code | Auto-generated from existing doc comments |
| **Conceptual Guides** | `.docc/` articles | Tutorials, explanations, architecture docs |

**Example from mlx-swift:**

1. **Docstrings → Automatic API Reference**

   Existing docstrings in source files:
   ```swift
   /// Number of elements in the 0th dimension.
   ///
   /// For example, these would be equivalent:
   ///
   /// ```swift
   /// for row in array {
   ///     ...
   /// }
   /// ```
   public var count: Int { dim(0) }
   ```

   These automatically become browsable API documentation on Swift Package Index.

2. **DocC Landing Page (`MLX.md`) → Curates & Organizes**

   ```markdown
   # ``MLX``

   MLX Swift is a Swift API for MLX...

   ## Topics

   ### MLXArray
   - ``MLXArray``

   ### Data Types
   - ``DType``
   - ``HasDType``
   ```

   The `## Topics` section organizes auto-generated API reference into logical groups.

3. **Symbol Extension Pages (`MLXArray.md`) → Adds Context**

   ```markdown
   # ``MLX/MLXArray``

   An N dimensional array. The main type in `mlx`.

   ## Thread Safety

   > `MLXArray` is not thread safe.

   Although `MLXArray` looks like a normal multidimensional array...
   ```

   These *extend* the docstring documentation with richer explanations, warnings, and examples.

4. **Articles (`Articles/lazy-evaluation.md`) → Conceptual Guides**

   ```markdown
   # Lazy Evaluation

   Computation in `MLX` is lazy...

   The actual computation only happens if an ``eval(_:)-3b2g9`` is performed...
   ```

   Articles provide conceptual explanations and link to symbols with ``` ``SymbolName`` ``` syntax.

**For MCP Swift SDK:**

The existing docstrings in the codebase will automatically become API reference. The README content becomes conceptual articles:

| Current Source | Becomes |
|----------------|---------|
| Docstrings in `Client.swift` | API reference for `Client` |
| Docstrings in `Server.swift` | API reference for `Server` |
| Docstrings in `Transport.swift` | API reference for transports |
| README "Client Usage" section | `Articles/ClientGuide.md` |
| README "Server Usage" section | `Articles/ServerGuide.md` |
| New `MCP.md` landing page | Organizes & links everything |

### How Swift Packages Link to Documentation

**mlx-swift** - Navigation bar at top:
```markdown
[**Installation**](#installation) | [**Documentation**](https://swiftpackageindex.com/ml-explore/mlx-swift/main/documentation/mlx) | [**Examples**](#examples)
```

**hummingbird** - Dedicated section:
```markdown
## Documentation

You can find reference documentation and user guides for Hummingbird [here](https://docs.hummingbird.codes/2.0/documentation/hummingbird/).
```

## Recommended Approach

Use DocC for documentation, hosted on Swift Package Index, with a concise README linking to it.

### New Structure

```
README.md                              # Concise (~150-200 lines)
.spi.yml                               # Configure SPI documentation targets
Sources/MCP/Documentation.docc/
├── MCP.md                             # Landing page
├── Resources/                         # Images (if needed)
└── Articles/
    ├── GettingStarted.md              # Quick start guide
    ├── ClientGuide.md                 # Full client documentation
    ├── ServerGuide.md                 # Full server documentation
    ├── Transports.md                  # Transport options & custom implementation
    └── Debugging.md                   # Logging & troubleshooting
```

### README Content

The new README will include:
- Navigation bar linking to SPI docs (like mlx-swift)
- Brief overview
- Installation instructions
- Quick start example (basic client + server)
- Platform availability table
- Links to full documentation

Example navigation bar:
```markdown
[**Installation**](#installation) | [**Documentation**](https://swiftpackageindex.com/modelcontextprotocol/swift-sdk/main/documentation/mcp) | [**Examples**](Examples/)
```

### Content Migration

| Current README Section | → DocC Location |
|----------------------|-----------------|
| Overview | `MCP.md` (landing page) |
| Requirements | `MCP.md` |
| Installation | `MCP.md` + README |
| Client Usage (basic) | `Articles/GettingStarted.md` |
| Client Usage (full) | `Articles/ClientGuide.md` |
| Server Usage (full) | `Articles/ServerGuide.md` |
| Transports | `Articles/Transports.md` |
| Platform Availability | `MCP.md` + README |
| Debugging and Logging | `Articles/Debugging.md` |

### Syntax Adjustments

DocC uses standard markdown with minor differences:

| GitHub Markdown | DocC Equivalent |
|----------------|-----------------|
| `> [!NOTE]` | `> Note:` |
| `> [!TIP]` | `> Tip:` |
| `> [!IMPORTANT]` | `> Important:` |
| `[link](#section)` | `<doc:ArticleName#section>` or standard links |
| `` `Symbol` `` | ``` ``Symbol`` ``` (double backticks for symbol links) |

Mermaid diagrams can be kept as-is (or converted to images if needed).

### .spi.yml Configuration

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MCP]
```

## Implementation Steps

1. **Create DocC bundle structure**
   - Create `Sources/MCP/Documentation.docc/` directory
   - Create `MCP.md` landing page
   - Create `Articles/` subdirectory

2. **Migrate content to DocC articles**
   - Extract client documentation → `ClientGuide.md`
   - Extract server documentation → `ServerGuide.md`
   - Extract transport documentation → `Transports.md`
   - Extract debugging documentation → `Debugging.md`
   - Create quick start → `GettingStarted.md`

3. **Update syntax**
   - Convert GitHub alert syntax to DocC format
   - Update internal links to use DocC syntax where beneficial
   - Keep standard markdown links for GitHub compatibility

4. **Rewrite README**
   - Add navigation bar with SPI documentation link
   - Keep overview, installation, quick example
   - Keep platform availability table
   - Remove detailed guides (now in DocC)

5. **Update .spi.yml**
   - Add `documentation_targets: [MCP]`

6. **Test locally**
   - Build DocC documentation: `swift package generate-documentation`
   - Preview documentation locally

7. **Verify on Swift Package Index**
   - After merge, verify documentation renders on SPI

## Benefits

- **Follows Swift ecosystem conventions** - Matches patterns used by mlx-swift, swift-transformers, etc.
- **Better discoverability** - Swift Package Index hosts and indexes the documentation
- **Cleaner README** - Quick reference for developers, not a wall of text
- **Richer documentation** - DocC supports tutorials, code snippets, symbol linking
- **Consistent with Apple platforms** - DocC is the standard for Swift documentation

## Decisions

The following decisions were made during planning:

### Protocol Version
- Update all spec references from 2025-03-26 to **2025-11-25** (latest supported)
- Spec links should point to `https://modelcontextprotocol.io/specification/2025-11-25/`

### .spi.yml
- Create `.spi.yml` with `documentation_targets: [MCP]`

### Examples
- Add brief mention in README pointing to `Examples/`
- Create `Articles/Examples.md` in DocC with detailed integration patterns
- Cover both Hummingbird and Vapor integrations

### Experimental Features (Tasks)
- Document fully in `Articles/Experimental.md`
- Include clear note at top about experimental status and potential API changes
- Follow Python SDK pattern of documenting experimental features

### Deprecated APIs
- Document only current recommended APIs
- Do not document deprecated methods (`withMethodHandler`, old `Prompt.Message.init`, `Client.initialize`)
- Users will receive compiler warnings guiding them to new APIs

## Publishing to Swift Package Index

Swift Package Index automatically discovers and indexes public Swift packages. Documentation is generated from DocC bundles when configured via `.spi.yml`.

### Steps to Publish

1. **Add the package to Swift Package Index**
   - Go to https://swiftpackageindex.com/add-a-package
   - Enter the repository URL (e.g., `https://github.com/modelcontextprotocol/swift-sdk`)
   - Submit for indexing

2. **Wait for initial indexing**
   - SPI crawls GitHub periodically
   - New packages typically appear within a few hours
   - You can check status at `https://swiftpackageindex.com/[owner]/[repo]`

3. **Documentation generation**
   - SPI automatically detects `.spi.yml` and generates DocC documentation
   - Documentation URL format: `https://swiftpackageindex.com/[owner]/[repo]/[version]/documentation/[target]`
   - For this SDK: `https://swiftpackageindex.com/modelcontextprotocol/swift-sdk/main/documentation/mcp`

### .spi.yml Reference

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MCP]  # Targets to generate docs for
```

Additional options:
```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MCP]
      scheme: MCP                    # Optional: specify build scheme
      platform: macos                # Optional: platform for doc generation
```

### Triggering Documentation Updates

Documentation regenerates automatically when:
- New tags are pushed
- The `main` branch is updated
- SPI's periodic re-indexing runs (~daily)

To manually trigger a rebuild:
1. Go to the package page on SPI
2. Click "..." menu → "Build Package"
3. Or push a new commit/tag

### Verifying Documentation

After publishing:
1. Visit the SPI package page
2. Click "Documentation" in the sidebar
3. Verify all articles appear in the navigation
4. Check that symbol links resolve correctly

### Troubleshooting

**Documentation not appearing:**
- Ensure `.spi.yml` is in the repository root
- Verify `documentation_targets` matches your target name exactly
- Check SPI build logs for errors

**Build failures:**
- SPI builds on Linux by default; ensure code compiles on Linux
- Platform-specific code should use `#if` conditionals
- Check that all dependencies are available on the target platform

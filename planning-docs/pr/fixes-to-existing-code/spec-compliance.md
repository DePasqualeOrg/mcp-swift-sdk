# Spec Compliance Fixes in PR #175

The following are improvements made to the existing codebase in PR [#175](https://github.com/modelcontextprotocol/swift-sdk/pull/175).

## Bug Fixes for 2025-03-26 Compliance

These are fixes for code that was incorrectly implemented relative to the 2025-03-26 spec.

### 1. Response Content-Type Validation

**Spec**: "If the input is a JSON-RPC request, the server MUST either return `Content-Type: text/event-stream`, to initiate an SSE stream, or `Content-Type: application/json`, to return one JSON object."

- [Spec reference (transports.mdx L105-108)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-03-26/basic/transports.mdx#L105-L108)
- [Original code (HTTPClientTransport.swift L266-272)](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Base/Transports/HTTPClientTransport.swift#L266-L272) - validates content-type for all responses, not just requests

**Issue**: Content-type was validated for all responses, but per spec should only be validated for requests.

**Fix**: Added `isRequest()` helper to distinguish request messages and validate content-type only for requests per spec.

**Location**: `Sources/MCP/Base/Transports/HTTPClientTransport.swift`

---

### 2. Notification Response Must Be 202 Accepted

**Spec**: "If the input is a JSON-RPC response or notification: If the server accepts the input, the server MUST return HTTP status code 202 Accepted with no body."

- [Spec reference (transports.mdx L98-101)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-03-26/basic/transports.mdx#L98-L101)
- [Original code (HTTPClientTransport.swift L263-273)](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Base/Transports/HTTPClientTransport.swift#L263-L273) - expects JSON/SSE content for all 2xx responses

**Issue**: The client expected a JSON or SSE response for all messages, but notifications should return 202 with no body.

**Fix**: Client now correctly expects 202 with no body for notifications.

**Location**: `Sources/MCP/Base/Transports/HTTPClientTransport.swift`

---

### 3. EmbeddedResource Structure

**Spec**: EmbeddedResource has `type: "resource"` and a nested `resource` object containing the actual content.

- [Spec reference (schema.ts L654-662)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-03-26/schema.ts#L654-L662)
- [Original code (Tools.swift L107)](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Server/Tools.swift#L107)

**Before (incorrect)**:
```swift
case resource(uri: String, mimeType: String, text: String?)
```

**After (correct per spec)**:
```swift
case resource(resource: Resource.Content, annotations: ContentAnnotations?, _meta: [String: Value]?)
```

**Locations**: `Sources/MCP/Server/Tools.swift`, `Sources/MCP/Server/Prompts.swift`

---

## New Functionality for 2025-03-26 Compliance

These are features that were in the 2025-03-26 spec but were not implemented in the existing codebase.

### 4. Content Annotations Structure

**Spec**: All content blocks (text, image, audio, embedded resource) support optional `annotations` with `audience`, `priority`, and `lastModified` fields.

- [Spec reference (schema.ts L475, L518, L661)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-03-26/schema.ts#L475)
- [Original code (Tools.swift L101-107)](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Server/Tools.swift#L101-L107) - missing annotations

**Issue**: Content types didn't include annotations.

**Fix**:
```swift
case text(String, annotations: ContentAnnotations?, _meta: [String: Value]?)
case image(data: String, mimeType: String, annotations: ContentAnnotations?, _meta: [String: Value]?)
case audio(data: String, mimeType: String, annotations: ContentAnnotations?, _meta: [String: Value]?)
case resource(resource: Resource.Content, annotations: ContentAnnotations?, _meta: [String: Value]?)
```

**Locations**: `Sources/MCP/Server/Tools.swift`, `Sources/MCP/Server/Prompts.swift`

---

### 5. Resource Not Found Error Code

**Spec**: "Servers SHOULD return standard JSON-RPC errors for common failure cases: Resource not found: `-32002`"

- [Spec reference (resources.mdx L335)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-03-26/server/resources.mdx#L335)
- [Original code (Error.swift)](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Base/Error.swift) - no `-32002` constant

**Issue**: Error code for resource not found wasn't defined.

**Fix**: Added `ErrorCode.resourceNotFound = -32002` constant.

**Location**: `Sources/MCP/Base/Error.swift`

---

### 6. _meta Field Support

**Spec**: "See General fields: `_meta` for notes on `_meta` usage." - All request params, notification params, and results support `_meta`.

- [Spec reference (schema.ts L40-46)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-03-26/schema.ts#L40-L46)

**Issue**: `_meta` wasn't supported on most types.

**Fix**: Added `_meta: [String: Value]?` to all request parameters, notification parameters, and result types.

**Locations**: Throughout `Sources/MCP/Server/*.swift`, `Sources/MCP/Client/*.swift`, `Sources/MCP/Base/*.swift`

---

### 7. RequestMeta with progressToken

**Spec**: Request `_meta` can include `progressToken` for progress notifications.

- [Spec reference (schema.ts L44)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-03-26/schema.ts#L44)

**Issue**: No structured type for request metadata.

**Fix**: Added `RequestMeta` type:
```swift
public struct RequestMeta: Hashable, Codable, Sendable {
    public var progressToken: ProgressToken?
}
```

**Location**: `Sources/MCP/Base/Progress.swift`

---

### 8. Extra Fields Preservation

**Spec**: Result types use `[key: string]: unknown` to allow additional fields for forward compatibility.

- [Spec reference (schema.ts L57, L66)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-03-26/schema.ts#L57)

**Issue**: Unknown fields in results were silently dropped during decoding.

**Fix**: Added `ResultWithExtraFields` protocol that preserves unknown fields:
```swift
public protocol ResultWithExtraFields: Codable, Sendable, Hashable {
    var extraFields: [String: Value]? { get set }
}
```

**Location**: `Sources/MCP/Base/Utilities/ExtraFieldsCoding.swift`

---

### 9. Role Type Shared Across Contexts

**Spec**: `Role` is a shared type (`"user"` | `"assistant"`) used in sampling, prompts, and other contexts.

- [Spec reference (schema.ts L635)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-03-26/schema.ts#L635)
- [Original code - Sampling.swift L12](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Client/Sampling.swift#L12) - local `Role` enum
- [Original code - Prompts.swift L44](https://github.com/modelcontextprotocol/swift-sdk/blob/main/Sources/MCP/Server/Prompts.swift#L44) - separate local `Role` enum

**Issue**: `Role` was defined locally in `Prompt.Message` and `Sampling.Message`.

**Fix**: Created top-level `Role` enum and added backwards-compatible type aliases.

**Location**: `Sources/MCP/Base/Annotations.swift` (top-level `Role`)

---

## Updates for 2025-06-18 and 2025-11-25 Compliance

These are features added in later spec versions.

### 10. Protocol Version Header Required for HTTP (2025-06-18)

**Spec**: "If using HTTP, the client MUST include the `MCP-Protocol-Version: <protocol-version>` HTTP header on all subsequent requests to the MCP server."

- [Spec reference (2025-06-18 transports.mdx L244-248)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-06-18/basic/transports.mdx#L244-L248)

**Issue**: The client didn't send this header.

**Fix**: Added `MCP-Protocol-Version` header to all HTTP requests after initialization.

**Location**: `Sources/MCP/Base/Transports/HTTPClientTransport.swift`

---

### 11. Default Protocol Version for Missing Header (2025-06-18)

**Spec**: "For backwards compatibility, if the server does not receive an `MCP-Protocol-Version` header, and has no other way to identify the version... the server SHOULD assume protocol version `2025-03-26`."

- [Spec reference (2025-06-18 transports.mdx L253-256)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-06-18/basic/transports.mdx#L253-L256)

**Issue**: No default version was assumed.

**Fix**: Added `Version.defaultNegotiated = "2025-03-26"` constant and server-side handling.

**Location**: `Sources/MCP/Base/Versioning.swift`

---

### 12. ResourceLink Content Type (2025-06-18)

**Spec**: Tools can return `resource_link` content type with `type: "resource_link"`.

- [Spec reference (2025-06-18 schema.ts L763)](https://github.com/modelcontextprotocol/specification/blob/main/schema/2025-06-18/schema.ts#L763)

**Issue**: SDK didn't support `resource_link` content type.

**Fix**: Added `ResourceLink` type and `.resourceLink(ResourceLink)` case to content enums.

**Location**: `Sources/MCP/Server/Tools.swift`, `Sources/MCP/Server/Resources.swift`

---

### 13. URL Elicitation Required Error Code (2025-11-25)

**Spec**: Error code `-32042` indicates the server requires URL elicitation.

- [Spec reference (2025-11-25 elicitation.mdx L421)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-11-25/client/elicitation.mdx#L421)

**Issue**: Error code wasn't defined.

**Fix**: Added `ErrorCode.urlElicitationRequired = -32042` constant.

**Location**: `Sources/MCP/Base/Error.swift`

---

### 14. Tool Name Validation (2025-11-25)

**Spec**: "Tool names SHOULD be between 1 and 128 characters in length... The following SHOULD be the only allowed characters: uppercase and lowercase ASCII letters (A-Z, a-z), digits (0-9), underscore (_), hyphen (-), and dot (.)."

- [Spec reference (2025-11-25 tools.mdx L216-220)](https://github.com/modelcontextprotocol/specification/blob/main/docs/specification/2025-11-25/server/tools.mdx#L216-L220)

**Issue**: No validation of tool names.

**Fix**: Added `ToolNameValidation` that warns on invalid tool names per spec.

**Location**: `Sources/MCP/Server/ToolNameValidation.swift`

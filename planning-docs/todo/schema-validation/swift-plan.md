# Schema Validation Comparison: Swift, Python, and TypeScript SDKs

This document compares schema validation implementations across the three official MCP SDKs to identify gaps in the Swift SDK and plan how to address them.

## Executive Summary

| Capability | TypeScript | Python | Swift |
|------------|------------|--------|-------|
| JSON Schema Validation Library | AJV / CfWorker | jsonschema | None |
| Tool Input Schema Validation (server) | ✅ | ✅ | ❌ |
| Tool Output Schema Validation (server) | ✅ | ✅ | ❌ |
| Tool Output Schema Validation (client) | ✅ | ✅ | ❌ |
| Elicitation Response Validation | ✅ | ✅ | ❌ |
| Tool Name Validation | ❌ | ✅ | ✅ |
| Message Deserialization | Zod | Pydantic | Codable |
| Sampling Message Validation | ✅ | ✅ | ✅ (already implemented) |

**Summary:** The Swift SDK is missing all JSON Schema validation (tools and elicitation). The ideal solution is a single JSON Schema validator for both, matching how TypeScript handles it. While elicitation *could* be implemented with custom validation on the typed Swift structs, using JSON Schema validation ensures spec compliance and consistency with other SDKs. Sampling message validation is already implemented.

---

## 1. Validation Infrastructure

### TypeScript SDK

- **Primary Library:** AJV (Ajv JSON Schema Validator)
- **Alternative:** @cfworker/json-schema for edge runtimes
- **Message Validation:** Zod (both v3 and v4 via compatibility layer)
- **Architecture:** Pluggable `jsonSchemaValidator` interface

```typescript
// Provider interface
export interface jsonSchemaValidator {
    getValidator<T>(schema: JsonSchemaType): JsonSchemaValidator<T>;
}

// Configurable on Server/Client
const server = new Server(serverInfo, {
    jsonSchemaValidator: new CfWorkerJsonSchemaValidator()
});
```

### Python SDK

- **Primary Library:** `jsonschema` for runtime JSON Schema validation
- **Message Validation:** Pydantic `model_validate()` for all message types
- **Function Validation:** Dynamic Pydantic models from function signatures
- **Schema Generation:** `StrictJsonSchema` for output schemas from type annotations

```python
# Tool input validation
jsonschema.validate(instance=arguments, schema=tool.inputSchema)

# Message validation
validated_request = self._receive_request_type.model_validate(message)
```

### Swift SDK

- **Primary Library:** None (acknowledged gap)
- **Message Validation:** Swift Codable with custom implementations
- **Architecture:** No pluggable validation system

**Current TODO comment in Server.swift:1153-1157:**
```swift
// TODO: Add response validation against the requested schema.
// TypeScript SDK uses JSON Schema validators (AJV, CfWorker) to validate
// elicitation responses against the requestedSchema. Python SDK uses Pydantic.
// Swift SDK currently lacks a JSON Schema validation library.
```

---

## 2. Schema Availability at Validation Points

A critical question for implementing validation: **are the schemas accessible where validation needs to happen?**

### Summary

| Validation Point | TypeScript | Python | Swift |
|------------------|------------|--------|-------|
| Elicitation response | ✅ Schema in request params | ✅ Schema in request params | ✅ Schema in request params |
| Tool input (server) | ✅ Tool registry lookup | ✅ Tool cache lookup | ❌ No tool cache |
| Tool output (server) | ✅ Tool registry lookup | ✅ Tool cache lookup | ❌ No tool cache |
| Tool output (client) | ✅ Cached from listTools | ✅ Cached from listTools | ❌ No caching |

### Elicitation: Schema IS Available

In all three SDKs, the `elicit()` method receives the `requestedSchema` as part of the request parameters. When the response comes back, the schema is still in scope:

```swift
// Swift SDK - Server.swift:1132-1159
public func elicit(_ params: Elicit.Parameters) async throws -> Elicit.Result {
    // params contains requestedSchema for form mode
    let result = try await sendRequest(request)

    // Schema is available here for validation:
    if case .form(let formParams) = params, result.action == .accept {
        try formParams.requestedSchema.validate(result.content)  // Can be added
    }
    return result
}
```

**Conclusion:** Elicitation validation can be implemented immediately with no infrastructure changes.

### Tool Validation: Architectural Differences

**Python/TypeScript approach:**
- Server maintains a **tool cache** populated from `list_tools()` handler
- On `call_tool`, looks up tool by name in cache to get `inputSchema`/`outputSchema`
- If tool not in cache: Python logs warning and skips; TypeScript refreshes

```python
# Python - server.py
# Tool cache populated from list_tools handler
if validate_input and tool:  # 'tool' looked up from cache
    jsonschema.validate(instance=arguments, schema=tool.inputSchema)
```

**Swift approach:**
- No tool registry or cache
- `withRequestHandler(CallTool.self)` receives only the request params
- Handler has no access to the `Tool` definition with its schemas

```swift
// Swift - current architecture
server.withRequestHandler(CallTool.self) { params, context in
    // params.name = tool name
    // params.arguments = arguments to validate
    // BUT: no access to Tool.inputSchema or Tool.outputSchema
    return try await executeTool(params.name, params.arguments)
}
```

### Required Infrastructure for Tool Validation

To implement tool input/output validation in Swift, the SDK would need:

1. **Tool cache in Server:**
   ```swift
   private var toolCache: [String: Tool] = [:]
   ```

2. **Cache population from ListTools handler:**
   ```swift
   // When ListTools handler is registered, intercept results to cache
   withRequestHandler(ListTools.self) { params, context in
       let result = try await userHandler(params, context)
       self.toolCache = Dictionary(uniqueKeysWithValues: result.tools.map { ($0.name, $0) })
       return result
   }
   ```

3. **Lookup during CallTool:**
   ```swift
   // Wrap CallTool handler with validation
   if let tool = toolCache[params.name] {
       try validate(params.arguments, against: tool.inputSchema)
   }
   let result = try await userHandler(params, context)
   if let tool = toolCache[params.name], let outputSchema = tool.outputSchema {
       try validate(result.structuredContent, against: outputSchema)
   }
   ```

This is a more significant architectural change than elicitation validation.

---

## 3. Tool Input Schema Validation (Detail)

### TypeScript SDK

**Location:** `packages/server/src/server/mcp.ts`

Validates tool arguments against the registered `inputSchema` before calling the handler:

```typescript
private async validateToolInput<Args>(tool: Tool, args: Args, toolName: string): Promise<Args> {
    if (!tool.inputSchema) {
        return undefined as Args;
    }

    const parseResult = await safeParseAsync(schemaToParse, args);
    if (!parseResult.success) {
        throw new McpError(
            ErrorCode.InvalidParams,
            `Input validation error: Invalid arguments for tool ${toolName}: ${errorMessage}`
        );
    }
    return parseResult.data as Args;
}
```

### Python SDK

**Location:** `src/mcp/server/lowlevel/server.py:520-534`

Uses `jsonschema.validate()` on incoming tool arguments:

```python
if validate_input and tool:
    try:
        jsonschema.validate(instance=arguments, schema=tool.inputSchema)
    except jsonschema.ValidationError as e:
        return self._make_error_result(f"Input validation error: {e.message}")
```

**Key Features:**
- Validation enabled by default
- Can be disabled per-tool with `validate_input=False`
- Tool cache populated by `list_tools()`

### Swift SDK

**Location:** `Sources/MCP/Server/Tools.swift:375-377`

**Current State:** No validation exists.

```swift
// inputSchema is stored but never validated against
public let inputSchema: Value  // Line 20

// Arguments received without validation
public let arguments: [String: Value]?  // Line 377
```

**Gap:** Tool arguments are accepted regardless of whether they conform to the declared `inputSchema`.

---

## 4. Tool Output Schema Validation (Detail)

### TypeScript SDK

**Location:** `packages/server/src/server/mcp.ts`

Validates tool results against `outputSchema` after handler execution:

```typescript
private async validateToolOutput(tool: RegisteredTool, result: CallToolResult, toolName: string): Promise<void> {
    if (!tool.outputSchema) return;
    if (result.isError) return;

    if (!result.structuredContent) {
        throw new McpError(
            ErrorCode.InvalidParams,
            `Tool ${toolName} has an output schema but no structured content was provided`
        );
    }

    const parseResult = await safeParseAsync(outputObj, result.structuredContent);
    if (!parseResult.success) {
        throw new McpError(
            ErrorCode.InvalidParams,
            `Output validation error: Invalid structured content for tool ${toolName}: ${errorMessage}`
        );
    }
}
```

### Python SDK

**Location:** `src/mcp/server/lowlevel/server.py:545-556`

```python
if tool and tool.outputSchema is not None:
    if maybe_structured_content is None:
        return self._make_error_result(
            "Output validation error: outputSchema defined but no structured output returned"
        )
    else:
        try:
            jsonschema.validate(instance=maybe_structured_content, schema=tool.outputSchema)
        except jsonschema.ValidationError as e:
            return self._make_error_result(f"Output validation error: {e.message}")
```

**Client-Side Validation (Python):**

The Python SDK also validates on the client when receiving tool results:

```python
async def _validate_tool_result(self, name: str, result: types.CallToolResult) -> None:
    output_schema = self._tool_output_schemas.get(name)
    if output_schema is not None:
        if result.structuredContent is None:
            raise RuntimeError(f"Tool {name} has an output schema but did not return structured content")
        validate(result.structuredContent, output_schema)
```

### Swift SDK

**Location:** `Sources/MCP/Server/Tools.swift:404-405`

**Current State:** No validation exists.

```swift
public let outputSchema: Value?  // Line 23, stored but unused

public let structuredContent: Value?  // Line 405, accepted without validation
```

**Gap:** Both server-side output validation and client-side result validation are missing.

---

## 5. Elicitation Schema Validation

### TypeScript SDK

**Location:** `packages/server/src/server/server.ts`

Validates elicitation responses against the requested schema:

```typescript
if (result.action === 'accept' && result.content && formParams.requestedSchema) {
    const validator = this._jsonSchemaValidator.getValidator(formParams.requestedSchema);
    const validationResult = validator(result.content);

    if (!validationResult.valid) {
        throw new McpError(
            ErrorCode.InvalidParams,
            `Elicitation response content does not match requested schema: ${validationResult.errorMessage}`
        );
    }
}
```

**Client-Side (TypeScript):**
- Applies schema defaults to responses when configured
- Validates request and result structures

### Python SDK

**Location:** `src/mcp/server/elicitation.py:52-102`

Python validates elicitation schemas at definition time to ensure only primitive types:

```python
_ELICITATION_PRIMITIVE_TYPES = (str, int, float, bool)

def _validate_elicitation_schema(schema: type[BaseModel]) -> None:
    for field_name, field_info in schema.model_fields.items():
        annotation = field_info.annotation
        if not _is_primitive_field(annotation) and not _is_string_sequence(annotation):
            raise TypeError(
                f"Elicitation schema field '{field_name}' must be a primitive type..."
            )
```

**Runtime Validation:**
Response validation happens through Pydantic models during response deserialization.

### Swift SDK

**Location:** `Sources/MCP/Client/Elicitation.swift:52-55, 99-100, 281-282`

The Swift SDK defines schema constraints but does not enforce them:

```swift
// StringSchema - constraints defined but not validated
public var minLength: Int?   // Line 52
public var maxLength: Int?   // Line 53
public var pattern: String?  // Line 54 - regex pattern
public var format: String?   // Line 55

// NumberSchema - constraints defined but not validated
public var minimum: Double?  // Line 99
public var maximum: Double?  // Line 100

// Multi-select - constraints defined but not validated
public var minItems: Int?    // Line 281
public var maxItems: Int?    // Line 282
```

**Gap:** All elicitation schema constraints are stored as metadata but never enforced on responses.

---

## 6. Tool Name Validation

### TypeScript SDK

**Status:** Not implemented (gap compared to Python/Swift)

### Python SDK

**Location:** `src/mcp/shared/tool_name_validation.py`

```python
TOOL_NAME_REGEX = re.compile(r"^[A-Za-z0-9._-]{1,128}$")

def validate_tool_name(name: str) -> ToolNameValidationResult:
    # Length: 1-128 characters
    # Characters: A-Z, a-z, 0-9, _, -, .
    # Warnings for: spaces, commas, leading/trailing dashes and dots
```

### Swift SDK

**Location:** `Sources/MCP/Server/ToolNameValidation.swift:23-84`

```swift
private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

public static func validateToolName(_ name: String) -> ToolNameValidationResult {
    // Length: 1-128 characters
    // Characters: A-Z, a-z, 0-9, _, -, .
    // Warnings for: spaces, commas, leading/trailing dashes and dots
}
```

**Status:** ✅ Full parity with Python SDK. Tests at `Tests/MCPTests/ToolTests.swift:508-652`.

---

## 7. Message Deserialization Validation

### TypeScript SDK

Uses Zod schemas for all protocol messages:

```typescript
// Type guards using Zod
export const isJSONRPCRequest = (value: unknown): value is JSONRPCRequest =>
    JSONRPCRequestSchema.safeParse(value).success;

// Message parsing
export function deserializeMessage(line: string): JSONRPCMessage {
    return JSONRPCMessageSchema.parse(JSON.parse(line));
}
```

### Python SDK

Uses Pydantic for all message types:

```python
# Response validation
return result_type.model_validate(response_or_error.result)

# Request validation
validated_request = self._receive_request_type.model_validate(message)
```

### Swift SDK

Uses Swift Codable with custom implementations:

```swift
// ID validation - validates string or number
public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
        self = .string(string)
    } else if let number = try? container.decode(Int.self) {
        self = .number(number)
    } else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "ID must be string or number")
    }
}

// JSON-RPC version validation
guard jsonrpc == "2.0" else {
    throw DecodingError.dataCorruptedError(...)
}
```

**Status:** Partial parity. Basic message structure validation exists through Codable, but lacks the runtime schema validation that Zod/Pydantic provide.

---

## 8. Sampling Message Validation

### TypeScript SDK

Validates sampling messages in the client handler wrapper:

```typescript
if (method === 'sampling/createMessage') {
    const validatedRequest = safeParse(CreateMessageRequestSchema, request);
    if (!validatedRequest.success) {
        throw new McpError(ErrorCode.InvalidParams, `Invalid sampling request: ${errorMessage}`);
    }
    // ... also validates result
}
```

### Python SDK

**Location:** `src/mcp/server/validation.py`

Comprehensive sampling validation:

```python
def validate_tool_use_result_messages(messages: list[SamplingMessage]) -> None:
    """
    Validate tool_use/tool_result message structure per SEP-1577.

    Ensures:
    1. Messages with tool_result content contain ONLY tool_result content
    2. tool_result messages are preceded by a message with tool_use
    3. tool_result IDs match the tool_use IDs from the previous message
    """
```

Also validates sampling capabilities:

```python
def validate_sampling_tools(client_caps, tools, tool_choice) -> None:
    if tools is not None or tool_choice is not None:
        if not check_sampling_tools_capability(client_caps):
            raise McpError(INVALID_PARAMS, "Client does not support sampling tools capability")
```

### Swift SDK

**Location:** `Sources/MCP/Client/Sampling.swift:747-780`

**Current State:** ✅ Full parity with Python SDK.

```swift
extension Sampling.Message {
    /// Validates the structure of tool_use/tool_result messages.
    public static func validateToolUseResultMessages(_ messages: [Sampling.Message]) throws {
        guard !messages.isEmpty else { return }

        let lastContent = messages[messages.count - 1].content
        let hasToolResults = lastContent.contains { if case .toolResult = $0 { return true }; return false }

        let previousContent: [ContentBlock]? = messages.count >= 2 ? messages[messages.count - 2].content : nil
        let hasPreviousToolUse = previousContent?.contains { if case .toolUse = $0 { return true }; return false } ?? false

        if hasToolResults {
            let hasNonToolResult = lastContent.contains { if case .toolResult = $0 { return false }; return true }
            if hasNonToolResult {
                throw MCPError.invalidParams("The last message must contain only tool_result content if any is present")
            }
            // ... validates tool_use precedes tool_result
            // ... validates IDs match
        }
    }
}
```

**Status:** Implements the same validation as Python's `validate_tool_use_result_messages`:
- ✅ Validates tool_result messages only contain tool_result content
- ✅ Ensures tool_result is preceded by tool_use
- ✅ Verifies toolUseId matches previous tool_use IDs

---

## 9. Implementation Gaps and Recommendations

### Ideal Solution: One JSON Schema Validator for All

Both tool schemas and elicitation schemas are **JSON Schema**. TypeScript uses the same validator (AJV/CfWorker) for both. For spec compliance and consistency, Swift should do the same.

| Gap | Priority | Effort | Recommendation |
|-----|----------|--------|----------------|
| Elicitation response validation | High | Medium | JSON Schema library |
| Tool input validation | High | Medium-High | JSON Schema library + tool cache |
| Tool output validation | High | Medium-High | JSON Schema library + tool cache |
| Client-side output validation | Medium | Medium | JSON Schema library + schema cache |

### Tool DSL Integration

The planned Tool DSL (see `../mcp-tool-dsl-design.md`) is designed to integrate seamlessly with this validation infrastructure:

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                         Server                               │
│    (Single source of validation via JSONSchemaValidator)     │
├─────────────────────────────────────────────────────────────┤
│  1. Validate input against inputSchema                       │
│  2. Execute tool (DSL via ToolRegistry, manual via handler)  │
│  3. Validate output against outputSchema (if present)        │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  DSL Tools    │   │ Manual Tools  │   │  Elicitation  │
│ (ToolRegistry │   │   (handler)   │   │   (Server)    │
│  parse+exec)  │   │               │   │               │
└───────────────┘   └───────────────┘   └───────────────┘
```

**Key design decisions:**

1. **Server is single source of validation** - Matches Python/TypeScript SDKs
2. **ToolRegistry does NOT validate** - Just parses and executes; Server validates before/after
3. **Constraints go in schema only** - `@Parameter(minLength: 1, maxLength: 100)` generates schema, Server enforces
4. **Defensive parsing with throwing errors** - `parse(from:)` uses guard + throw (not force unwraps)
5. **Simple string error messages** - Matches Python/TypeScript SDK behavior (see below)

### Validation Error Message Format

Both Python and TypeScript SDKs use **simple string messages** for validation errors—no structured error data (schema, value, path as separate fields).

**Python SDK** (`lowlevel/server.py:524-525`):
```python
except jsonschema.ValidationError as e:
    return self._make_error_result(f"Input validation error: {e.message}")
```

The `jsonschema` library's `e.message` includes the constraint violated, path, and sometimes the value.
Example: `"500 is greater than the maximum of 100"`

**TypeScript SDK** (`mcp.ts:279-280`):
```typescript
const errorMessage = getParseErrorMessage(error);
throw new McpError(ErrorCode.InvalidParams, `Input validation error: Invalid arguments for tool ${toolName}: ${errorMessage}`);
```

Zod's error message includes path and issue type.
Example: `"Expected number, received string"`

**Swift SDK approach:**
```swift
throw MCPError.invalidParams(
    "Input validation error: Invalid arguments for tool \(toolName): \(validatorMessage)"
)
```

Where `validatorMessage` is a descriptive string from the JSON Schema validator, e.g.:
- `"value 500 exceeds maximum 100 at path $.limit"`
- `"'invalid' is not one of ['pending', 'active'] at path $.status"`
- `"missing required property 'title'"`

**Key requirement:** The validator must produce **descriptive messages**. The error structure stays simple (just a string in `MCPError.invalidParams`).

**Benefits:**
- No duplicate validation (Server validates once, ToolRegistry trusts it)
- Consistent error messages across all tools
- Simpler ToolRegistry (no validator dependency)
- Matches Python/TypeScript architecture
- Server stays up on any failure (aligns with Python/TypeScript behavior)

### Why One Validator for Both?

**Spec compliance:** Elicitation `requestedSchema` IS JSON Schema (a restricted subset). Validating it as JSON Schema ensures semantics match the spec.

**Consistency:** TypeScript uses the same validator for tools and elicitation. This avoids divergence in validation behavior.

**Code elegance:** One validation system, one set of error messages, one mental model.

**Not a breaking change:** Adding validation to `elicit()` doesn't change the API - it's a behavioral improvement. Invalid responses that previously succeeded will now throw, which aligns with other SDKs.

**DSL compatibility:** The Tool DSL relies on this validator—it doesn't generate its own validation code.

### Why NOT Custom Elicitation Validation?

While the Swift SDK models elicitation schemas as typed structs (`StringSchema`, `NumberSchema`, etc.), custom validation would:

1. Risk diverging from JSON Schema semantics
2. Create two different validation systems to maintain
3. Not align with how TypeScript/Python handle it

The typed structs are useful for *constructing* schemas with compile-time safety, but validation should happen at the JSON Schema level.

### Infrastructure Requirements

**For tools:** The Swift SDK needs a **tool cache** because `CallTool` handlers don't receive the `Tool` definition. See [Section 2](#2-schema-availability-at-validation-points).

**For elicitation:** No infrastructure changes needed. The schema is available in `params.requestedSchema`. Implementation:

```swift
public func elicit(_ params: Elicit.Parameters) async throws -> Elicit.Result {
    let result = try await sendRequest(request)

    if case .form(let formParams) = params,
       result.action == .accept,
       let content = result.content {
        // Convert typed values to Value for JSON Schema validation
        let contentValue = content.asValue()
        let schemaValue = formParams.requestedSchema.asValue()
        try jsonSchemaValidator.validate(contentValue, against: schemaValue)
    }

    return result
}
```

### Already Implemented

| Feature | Location | Notes |
|---------|----------|-------|
| Sampling message validation | `Sampling.swift:747-780` | Full parity with Python |
| Tool name validation | `ToolNameValidation.swift` | Full parity with Python |

### Nice to Have

| Gap | Priority | Effort | Recommendation |
|-----|----------|--------|----------------|
| Prompt argument validation | Low | Low | Validate argument names and types |
| Resource URI validation | Low | Low | Basic URI format validation |
| Configurable validator | Low | Medium | Add pluggable validator interface like TypeScript |

---

## 10. Proposed Implementation Plan

### Relationship with Tool DSL

The JSON Schema validator is a **prerequisite** for the Tool DSL. The DSL design
(see `../mcp-tool-dsl-design.md`) assumes:

1. Validator exists and is integrated into Server/ToolRegistry
2. All constraint enforcement happens via validator
3. DSL-generated `parse(from:)` uses defensive guards (throws on failure, doesn't crash)

**Implementation order:**
1. Phase 1-3 below (JSON Schema validator + Server integration)
2. Tool DSL Phase 1-5 (see DSL design document)

### Phase 1: JSON Schema Validator

**Effort: Medium | Foundation for all validation**

#### Chosen Library: [ajevans99/swift-json-schema](https://github.com/ajevans99/swift-json-schema)

After evaluating available Swift JSON Schema libraries, we've chosen **swift-json-schema** for validation:

| Criteria | swift-json-schema | mattt/JSONSchema |
|----------|-------------------|------------------|
| **Validation** | ✅ Full support | ❌ None (by design) |
| **JSON Schema Draft** | draft-2020-12 (full) | draft-2020-12 (partial, definition only) |
| **Dependencies** | None for `JSONSchema` module | swift-collections |
| **Platform** | iOS 16+, macOS 13+, Linux | iOS 17+, macOS 14+ |
| **Maintenance** | Very active (Dec 2025) | Moderate |
| **MCP Integration** | Author has [swift-mcp-toolkit](https://github.com/ajevans99/swift-mcp-toolkit) | N/A |

**Key insight:** The library has two modules:
- `JSONSchema` — Core validation, **no external dependencies**
- `JSONSchemaBuilder` — Result builders + `@Schemable` macro (requires swift-syntax)

We only need the `JSONSchema` module for validation. The MCP SDK will use its own macros
(`@Tool`, `@Parameter`) which already require swift-syntax, so there's no additional burden.

#### Integration Approach

**Keep `Value`, add conversion methods.** MCP's `Value` type has a `.data(mimeType:, Data)` case
for binary content that `JSONValue` doesn't support. Rather than forking or typealiasing,
we add bidirectional conversion:

```swift
extension Value {
    /// Convert to JSONValue for validation.
    func toJSONValue() -> JSONValue {
        switch self {
        case .null: return .null
        case .bool(let b): return .boolean(b)
        case .int(let i): return .integer(i)
        case .double(let d): return .number(d)
        case .string(let s): return .string(s)
        case .data(let mimeType, let data):
            // Data URLs are validated as strings
            return .string(data.dataURLEncoded(mimeType: mimeType))
        case .array(let arr): return .array(arr.map { $0.toJSONValue() })
        case .object(let obj): return .object(obj.mapValues { $0.toJSONValue() })
        }
    }
}
```

Conversion only happens at validation boundaries—negligible overhead.

#### Validator Protocol

```swift
import JSONSchema

public protocol JSONSchemaValidator: Sendable {
    func validate(_ instance: Value, against schema: Value) throws
}

/// Default implementation wrapping swift-json-schema.
public struct DefaultJSONSchemaValidator: JSONSchemaValidator {
    public init() {}

    public func validate(_ instance: Value, against schema: Value) throws {
        let jsonInstance = instance.toJSONValue()
        let jsonSchema = schema.toJSONValue()

        let validator = try Schema(
            rawSchema: jsonSchema,
            context: .init(dialect: .draft2020_12)
        )
        let result = validator.validate(jsonInstance)

        if !result.isValid {
            let message = result.errors?.first?.message ?? "Validation failed"
            throw MCPError.invalidParams(message)
        }
    }
}
```

**Pluggable by design:** Following TypeScript's pattern (AJV vs CfWorker), the validator
is a protocol so implementations can be swapped:

```swift
// Use built-in validator (default)
let server = Server(info: impl, capabilities: caps)

// Use custom validator
let customValidator = MyCustomValidator()
let server = Server(info: impl, capabilities: caps, validator: customValidator)
```

#### Feature Coverage

All required features are supported by swift-json-schema:

| Feature | Needed For | swift-json-schema |
|---------|------------|-------------------|
| type (string, number, integer, boolean, object, array) | All | ✅ |
| properties, required | All | ✅ |
| minLength, maxLength, pattern, format | Elicitation, Tools | ✅ |
| minimum, maximum | Elicitation, Tools | ✅ |
| enum, const | Elicitation, Tools | ✅ |
| minItems, maxItems, items | Elicitation, Tools | ✅ |
| Nested objects | Tools | ✅ |
| allOf, anyOf, oneOf | Elicitation (titled enums), Tools | ✅ |
| $ref, $defs | Tools (rare) | ✅ |
| if/then/else | Tools (rare) | ✅ |
| Format validators (email, uri, date-time, etc.) | Elicitation | ✅ Built-in |

### Phase 2: Elicitation Validation

**Effort: Low | No infrastructure changes needed**

Add validation to `Server.elicit()`:

```swift
public func elicit(_ params: Elicit.Parameters) async throws -> Elicit.Result {
    let result = try await sendRequest(request)

    if case .form(let formParams) = params,
       result.action == .accept,
       let content = result.content {
        // Convert to Value for JSON Schema validation
        let contentValue = content.asValue()
        let schemaValue = formParams.requestedSchema.asValue()
        try jsonSchemaValidator.validate(contentValue, against: schemaValue)
    }

    return result
}
```

**Migration:** Not a breaking API change. Behavioral improvement - invalid responses now throw `MCPError.invalidParams`.

### Phase 3: Tool Cache Infrastructure + Server Integration

**Effort: Medium | Required for tool validation and DSL**

Add tool caching and validated tool handler to Server:

```swift
public actor Server {
  private let validator: JSONSchemaValidator
  private var toolCache: [String: Tool] = [:]
  private var toolRegistry: ToolRegistry?  // For DSL tools (added later)

  public init(
    info: Implementation,
    capabilities: ServerCapabilities,
    validator: JSONSchemaValidator = DefaultJSONSchemaValidator()
  ) {
    self.validator = validator
    // ...
  }

  /// Register tools for validation.
  public func registerTools(_ tools: [Tool]) {
    for tool in tools {
      toolCache[tool.name] = tool
    }
  }

  /// Register DSL tools via registry (used by Tool DSL).
  public func registerTools(_ registry: ToolRegistry) async {
    self.toolRegistry = registry
    for tool in await registry.definitions {
      toolCache[tool.name] = tool
    }
  }

  /// All registered tools.
  public var allTools: [Tool] {
    Array(toolCache.values)
  }

  /// Register a tool handler with automatic validation.
  public func withValidatedToolHandler(
    _ handler: @escaping (CallTool.Params, RequestContext) async throws -> CallTool.Result
  ) {
    withRequestHandler(CallTool.self) { [self] params, ctx in
      let name = params.name

      guard let tool = await self.toolCache[name] else {
        throw MCPError.methodNotFound("Unknown tool: \(name)")
      }

      // Validate input
      let inputValue: Value = params.arguments.map { .object($0) } ?? .object([:])
      try self.validator.validate(inputValue, against: tool.inputSchema)

      // Execute via registry if DSL tool
      if let registry = await self.toolRegistry,
         await registry.hasTool(name) {
        return try await registry.execute(name, arguments: params.arguments)
      }

      // Execute manual tool handler
      let result = try await handler(params, ctx)

      // Validate output if schema exists
      if let outputSchema = tool.outputSchema,
         let structured = result.structuredContent {
        try self.validator.validate(structured, against: outputSchema)
      }

      return result
    }
  }
}
```

This infrastructure supports both manual tools (Phase 4) and DSL tools (added later).

### Phase 4: Tool Input/Output Validation

**Effort: Low | Already implemented in Phase 3**

The `withValidatedToolHandler` from Phase 3 handles both input and output validation.

**Usage for manual tools:**
```swift
let tools = [
  Tool(name: "search", inputSchema: searchSchema, outputSchema: resultSchema)
]

server.registerTools(tools)

server.withRequestHandler(ListTools.self) { _, _ in
  ListTools.Result(tools: await server.allTools)
}

server.withValidatedToolHandler { params, ctx in
  // Input already validated
  switch params.name {
  case "search":
    return try await performSearch(params.arguments)
  default:
    throw MCPError.methodNotFound(params.name)
  }
}
```

**Options (future enhancement):**
- Add per-tool `validateInput: Bool` option (like Python)
- Make validation opt-in or opt-out via `ServerOptions`

### Phase 5: Client-Side Tool Output Validation

**Effort: Low | Requires Phase 1**

Cache tool output schemas from `listTools()` and validate received results:

```swift
// Client caches output schemas
private var toolOutputSchemas: [String: Value] = [:]

public func listTools(...) async throws -> ListTools.Result {
    let result = try await request(...)
    // Cache output schemas
    for tool in result.tools {
        if let schema = tool.outputSchema {
            toolOutputSchemas[tool.name] = schema
        }
    }
    return result
}

public func callTool(...) async throws -> CallTool.Result {
    let result = try await request(...)
    // Validate against cached schema
    if let schema = toolOutputSchemas[name],
       let structured = result.structuredContent {
        try jsonSchemaValidator.validate(structured, against: schema)
    }
    return result
}
```

---

## 11. Summary

### Ideal Solution: One JSON Schema Validator

Both elicitation and tool schemas are **JSON Schema**. The ideal solution is a single JSON Schema validator for all validation, matching TypeScript's approach.

| Validation | Schema Available? | Infrastructure Needed? |
|------------|-------------------|------------------------|
| Elicitation | ✅ In request params | None |
| Tool input/output (server) | ❌ Need tool cache | Tool cache |
| Tool output (client) | ❌ Need schema cache | Schema cache |
| DSL tools | ✅ Generated by macro | ToolRegistry |

### Tool DSL Integration

The JSON Schema validator is the **foundation** for the planned Tool DSL:

- Server is single source of validation (matches Python/TypeScript)
- ToolRegistry does NOT validate - just parses and executes
- DSL generates schemas, Server enforces them
- `parse(from:)` uses defensive guards with throwing errors (not force unwraps)
- Output schema validation handled by Server for all tools
- Server stays up on any error (aligns with Python/TypeScript behavior)

See `../mcp-tool-dsl-design.md` for full DSL design.

### Why Not Custom Elicitation Validation?

While Swift's typed structs (`StringSchema`, etc.) *could* be validated directly:

1. Elicitation schemas ARE JSON Schema - should be validated as such
2. Custom validation risks diverging from JSON Schema semantics
3. TypeScript uses the same validator for tools and elicitation
4. One system is more elegant than two

### Already Implemented (Parity with Python)

- **Tool name validation** (`ToolNameValidation.swift`)
- **Sampling message validation** (`Sampling.swift:747-780`)

### Implementation Phases

| Phase | What | Effort | Blocked By |
|-------|------|--------|------------|
| 1 | JSON Schema validator (swift-json-schema) | Medium | ✅ Library chosen |
| 2 | Elicitation validation | Low | Phase 1 |
| 3 | Tool cache + Server integration | Medium | - |
| 4 | Tool input/output validation | Low | Phase 3 (included) |
| 5 | Client-side output validation | Low | Phase 1 |
| — | **Tool DSL** | Medium | Phase 1-3 |

### Dependency: swift-json-schema

Add to `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/ajevans99/swift-json-schema", from: "0.2.1"),
],
targets: [
    .target(
        name: "MCP",
        dependencies: [
            .product(name: "JSONSchema", package: "swift-json-schema"),  // Validation only
            // Note: JSONSchemaBuilder NOT needed - MCP has its own macros
        ]
    ),
]
```

### Migration

Adding validation is **not a breaking API change**. It's a behavioral improvement where invalid data that previously succeeded will now throw `MCPError.invalidParams`. This aligns with TypeScript and Python SDK behavior.

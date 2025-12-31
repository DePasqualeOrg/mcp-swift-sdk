# Schema Validation in the MCP Python SDK

This document describes how schema validation is implemented throughout the MCP Python SDK.

## Overview

The SDK uses multiple validation strategies depending on the context:

| Validation Type | Library/Method | Location |
|-----------------|----------------|----------|
| Tool input/output schemas | `jsonschema.validate()` | Server and Client |
| Message deserialization | Pydantic `model_validate()` | Session layer |
| Function arguments | Pydantic dynamic models | FastMCP |
| Tool names | Regex pattern matching | Shared utilities |
| Elicitation schemas | Type introspection | Elicitation utilities |
| Sampling messages | Custom validation logic | Server validation |

---

## 1. Server-Side Tool Input/Output Validation

**File:** `src/mcp/server/lowlevel/server.py` (lines 520-562)

### Input Validation

When a `CallToolRequest` is received, the server validates the provided arguments against the tool's `inputSchema` using the `jsonschema` library:

```python
if validate_input and tool:
    try:
        jsonschema.validate(instance=arguments, schema=tool.inputSchema)
    except jsonschema.ValidationError as e:
        return self._make_error_result(f"Input validation error: {e.message}")
```

**Key behaviors:**
- Validation is enabled by default but can be disabled via `validate_input=False` on the `@server.call_tool()` decorator
- The tool definition is fetched from a cache populated by `list_tools()`
- If the tool is not found in the cache, validation is skipped with a warning logged

### Output Validation

After the tool handler executes, if the tool has an `outputSchema`, the structured content is validated:

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

**Key behaviors:**
- If `outputSchema` is defined but no structured content is returned, an error is returned
- Validation uses the same `jsonschema.validate()` function
- Validation errors are returned as tool error results (not exceptions)

---

## 2. Client-Side Output Schema Validation

**File:** `src/mcp/client/session.py` (lines 398-422)

When a client calls a tool and receives a result, it validates the structured content against the tool's declared `outputSchema`:

```python
async def _validate_tool_result(self, name: str, result: types.CallToolResult) -> None:
    """Validate the structured content of a tool result against its output schema."""
    if name not in self._tool_output_schemas:
        # refresh output schema cache
        await self.list_tools()

    output_schema = self._tool_output_schemas.get(name)

    if output_schema is not None:
        from jsonschema import SchemaError, ValidationError, validate

        if result.structuredContent is None:
            raise RuntimeError(
                f"Tool {name} has an output schema but did not return structured content"
            )
        try:
            validate(result.structuredContent, output_schema)
        except ValidationError as e:
            raise RuntimeError(f"Invalid structured content returned by tool {name}: {e}")
        except SchemaError as e:
            raise RuntimeError(f"Invalid schema for tool {name}: {e}")
```

**Key behaviors:**
- Output schemas are cached from `list_tools()` results in `self._tool_output_schemas`
- If the tool is not in the cache, `list_tools()` is called to refresh
- Validation uses `jsonschema.validate()`
- Errors are raised as `RuntimeError` (not returned as error results)
- Also catches `SchemaError` for invalid schema definitions

---

## 3. Pydantic Message Deserialization

**File:** `src/mcp/shared/session.py` (lines 307, 361, 398)

All incoming JSON-RPC messages are deserialized and validated using Pydantic's `model_validate()` method.

### Response Validation

```python
return result_type.model_validate(response_or_error.result)
```

### Request Validation

```python
validated_request = self._receive_request_type.model_validate(
    message.message.root.model_dump(by_alias=True, mode="json", exclude_none=True)
)
```

### Notification Validation

```python
notification = self._receive_notification_type.model_validate(
    message.message.root.model_dump(by_alias=True, mode="json", exclude_none=True)
)
```

**Key behaviors:**
- All MCP message types are defined as Pydantic `BaseModel` subclasses in `mcp/types.py`
- Uses `model_dump()` to serialize the raw JSON-RPC message, then `model_validate()` to parse into typed models
- Request validation errors result in a JSON-RPC error response with code `INVALID_PARAMS`
- The validated objects provide type-safe access to message fields

---

## 4. FastMCP Function Argument Validation

**File:** `src/mcp/server/fastmcp/utilities/func_metadata.py`

FastMCP uses Pydantic to validate function arguments before calling tool/resource/prompt handlers.

### Dynamic Model Creation

For each registered function, a Pydantic model is dynamically created from the function signature:

```python
arguments_model = create_model(
    f"{func.__name__}Arguments",
    __base__=ArgModelBase,
    **dynamic_pydantic_model_params,
)
```

The model is stored in `FuncMetadata.arg_model`.

### Argument Validation

When a tool is called, arguments are validated using the generated model:

```python
async def call_fn_with_arg_validation(
    self,
    fn: Callable[..., Any | Awaitable[Any]],
    fn_is_async: bool,
    arguments_to_validate: dict[str, Any],
    arguments_to_pass_directly: dict[str, Any] | None,
) -> Any:
    arguments_pre_parsed = self.pre_parse_json(arguments_to_validate)
    arguments_parsed_model = self.arg_model.model_validate(arguments_pre_parsed)
    arguments_parsed_dict = arguments_parsed_model.model_dump_one_level()
    # ... call function with validated arguments
```

**Key behaviors:**
- Arguments are first pre-parsed from JSON (handles cases where Claude sends JSON strings instead of objects)
- `model_validate()` validates against the dynamically-created Pydantic model
- Validation errors raise Pydantic's `ValidationError`

### Output Schema Generation

FastMCP also generates output schemas from return type annotations using `StrictJsonSchema`:

```python
class StrictJsonSchema(GenerateJsonSchema):
    """A JSON schema generator that raises exceptions instead of emitting warnings."""

    def emit_warning(self, kind: JsonSchemaWarningKind, detail: str) -> None:
        raise ValueError(f"JSON schema warning: {kind} - {detail}")
```

This ensures non-serializable types are detected at registration time rather than at runtime.

---

## 5. Tool Name Validation

**File:** `src/mcp/shared/tool_name_validation.py`

Tool names are validated against the SEP-986 specification using regex pattern matching.

### Validation Pattern

```python
TOOL_NAME_REGEX = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
```

### Validation Logic

```python
def validate_tool_name(name: str) -> ToolNameValidationResult:
    warnings: list[str] = []

    # Check for empty name
    if not name:
        return ToolNameValidationResult(is_valid=False, warnings=["Tool name cannot be empty"])

    # Check length
    if len(name) > 128:
        return ToolNameValidationResult(
            is_valid=False,
            warnings=[f"Tool name exceeds maximum length of 128 characters (current: {len(name)})"],
        )

    # Check for problematic patterns (warnings, not validation failures)
    if " " in name:
        warnings.append("Tool name contains spaces, which may cause parsing issues")

    # ... additional checks for commas, leading/trailing dashes and dots

    # Check for invalid characters
    if not TOOL_NAME_REGEX.match(name):
        # Find and report invalid characters
        # ...
        return ToolNameValidationResult(is_valid=False, warnings=warnings)

    return ToolNameValidationResult(is_valid=True, warnings=warnings)
```

**Key behaviors:**
- Names must be 1-128 characters
- Allowed characters: `A-Z`, `a-z`, `0-9`, `_`, `-`, `.`
- Spaces and commas generate warnings but don't fail validation
- Leading/trailing dashes and dots generate warnings
- Invalid characters cause validation failure
- Warnings are logged but tool registration proceeds

---

## 6. Elicitation Schema Validation

**File:** `src/mcp/server/elicitation.py` (lines 52-102)

Elicitation schemas are validated to ensure they only contain primitive types that can be safely rendered in a form UI.

### Allowed Types

```python
_ELICITATION_PRIMITIVE_TYPES = (str, int, float, bool)
```

Additionally, sequences of strings (`list[str]`, `Sequence[str]`) are allowed.

### Validation Logic

```python
def _validate_elicitation_schema(schema: type[BaseModel]) -> None:
    """Validate that a Pydantic model only contains primitive field types."""
    for field_name, field_info in schema.model_fields.items():
        annotation = field_info.annotation

        if annotation is None or annotation is types.NoneType:
            continue
        elif _is_primitive_field(annotation):
            continue
        elif _is_string_sequence(annotation):
            continue
        else:
            raise TypeError(
                f"Elicitation schema field '{field_name}' must be a primitive type "
                f"{_ELICITATION_PRIMITIVE_TYPES}, a sequence of strings (list[str], etc.), "
                f"or Optional of these types. Nested models and complex types are not allowed."
            )
```

### Helper Functions

**`_is_primitive_field`:** Checks if a type is a primitive or `Union`/`Optional` of primitives:

```python
def _is_primitive_field(annotation: type) -> bool:
    if annotation in _ELICITATION_PRIMITIVE_TYPES:
        return True

    origin = get_origin(annotation)
    if origin is Union or origin is types.UnionType:
        args = get_args(annotation)
        return all(
            arg is types.NoneType or arg in _ELICITATION_PRIMITIVE_TYPES or _is_string_sequence(arg)
            for arg in args
        )

    return False
```

**`_is_string_sequence`:** Checks if a type is a sequence of strings:

```python
def _is_string_sequence(annotation: type) -> bool:
    origin = get_origin(annotation)
    if origin:
        if issubclass(origin, Sequence):
            args = get_args(annotation)
            return len(args) == 1 and args[0] is str
    return False
```

**Key behaviors:**
- Validation happens at elicitation time, not registration time
- Raises `TypeError` if complex types are found
- Supports `Optional[T]` and `Union` types where all members are primitives

---

## 7. Sampling/Tool Use Message Validation

**File:** `src/mcp/server/validation.py`

### Capability Validation

Before using sampling tools, the server validates that the client supports them:

```python
def validate_sampling_tools(
    client_caps: ClientCapabilities | None,
    tools: list[Tool] | None,
    tool_choice: ToolChoice | None,
) -> None:
    if tools is not None or tool_choice is not None:
        if not check_sampling_tools_capability(client_caps):
            raise McpError(
                ErrorData(
                    code=INVALID_PARAMS,
                    message="Client does not support sampling tools capability",
                )
            )
```

### Message Structure Validation (SEP-1577)

Tool use and tool result messages are validated for correct structure:

```python
def validate_tool_use_result_messages(messages: list[SamplingMessage]) -> None:
    """
    Validate tool_use/tool_result message structure per SEP-1577.

    This validation ensures:
    1. Messages with tool_result content contain ONLY tool_result content
    2. tool_result messages are preceded by a message with tool_use
    3. tool_result IDs match the tool_use IDs from the previous message
    """
    last_content = messages[-1].content_as_list
    has_tool_results = any(c.type == "tool_result" for c in last_content)

    previous_content = messages[-2].content_as_list if len(messages) >= 2 else None
    has_previous_tool_use = previous_content and any(c.type == "tool_use" for c in previous_content)

    if has_tool_results:
        # Per spec: "SamplingMessage with tool result content blocks
        # MUST NOT contain other content types."
        if any(c.type != "tool_result" for c in last_content):
            raise ValueError("The last message must contain only tool_result content if any is present")
        if previous_content is None:
            raise ValueError("tool_result requires a previous message containing tool_use")
        if not has_previous_tool_use:
            raise ValueError("tool_result blocks do not match any tool_use in the previous message")

    if has_previous_tool_use and previous_content:
        tool_use_ids = {c.id for c in previous_content if c.type == "tool_use"}
        tool_result_ids = {c.toolUseId for c in last_content if c.type == "tool_result"}
        if tool_use_ids != tool_result_ids:
            raise ValueError("ids of tool_result blocks and tool_use blocks from previous message do not match")
```

**Key behaviors:**
- Validates that tool_result messages only contain tool_result content blocks
- Ensures tool_result messages are preceded by tool_use messages
- Verifies that tool_use IDs match corresponding tool_result IDs
- Raises `ValueError` for invalid structures
- Raises `McpError` for capability issues

---

## Summary

| Validation | When | Error Handling |
|------------|------|----------------|
| Tool input schema | On `call_tool` request | Returns error result |
| Tool output schema | After tool execution | Returns error result |
| Client output validation | After receiving tool result | Raises `RuntimeError` |
| Message deserialization | On message receipt | JSON-RPC error response |
| FastMCP arguments | Before calling handler | Raises `ValidationError` |
| Tool names | On tool registration | Logs warnings, proceeds |
| Elicitation schemas | On elicitation call | Raises `TypeError` |
| Sampling capabilities | Before sampling with tools | Raises `McpError` |
| Tool use/result structure | Before sampling | Raises `ValueError` |

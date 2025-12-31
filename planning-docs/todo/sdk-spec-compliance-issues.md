# MCP SDK Spec Compliance Issues

This document details spec compliance issues found in the MCP TypeScript and Python SDKs that should be addressed via pull requests.

## Issue 1: Unknown Tool Returns `isError: true` Instead of JSON-RPC Protocol Error

### Status: CONFIRMED

### MCP Specification Reference

The spec distinguishes between protocol errors and tool execution errors:

**Protocol Errors** (lines 248-251): https://github.com/modelcontextprotocol/modelcontextprotocol/blob/c1e0b4d39a630fd87807602c6ace6eefc15154a5/docs/specification/2025-03-26/server/tools.mdx#L248-L251

> 1. **Protocol Errors**: Standard JSON-RPC errors for issues like:
>    - Unknown tools
>    - Invalid arguments
>    - Server errors

**Tool Execution Errors** (lines 253-256): https://github.com/modelcontextprotocol/modelcontextprotocol/blob/c1e0b4d39a630fd87807602c6ace6eefc15154a5/docs/specification/2025-03-26/server/tools.mdx#L253-L256

> 2. **Tool Execution Errors**: Reported in tool results with `isError: true`:
>    - API failures
>    - Invalid input data
>    - Business logic errors

**Protocol error example for unknown tool** (lines 258-269): https://github.com/modelcontextprotocol/modelcontextprotocol/blob/c1e0b4d39a630fd87807602c6ace6eefc15154a5/docs/specification/2025-03-26/server/tools.mdx#L258-L269

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "error": {
    "code": -32602,
    "message": "Unknown tool: invalid_tool_name"
  }
}
```

### Current TypeScript SDK Behavior (WRONG)

**GitHub URL:** https://github.com/modelcontextprotocol/typescript-sdk/blob/5ce4b5ef086045629e1ad444785d2d1fdb137a09/packages/server/src/server/mcp.ts#L179-L232

The issue is that:
1. An `McpError` with `ErrorCode.InvalidParams` is thrown when tool is not found (line 183)
2. This error is caught by the outer catch block (line 226)
3. The error is converted to `isError: true` via `createToolError()` (line 232)

Only `UrlElicitationRequiredError` is re-thrown as a protocol error; `McpError` for unknown tools is incorrectly converted to a tool execution error.

### Current Python SDK Behavior (WRONG)

**GitHub URL:** https://github.com/modelcontextprotocol/python-sdk/blob/0da9a074d09267a927d72faa58c26d828f0f8edb/src/mcp/server/fastmcp/tools/tool_manager.py#L89-L91

The code raises `ToolError` instead of `McpError` for unknown tools:

```python
tool = self.get_tool(name)
if not tool:
    raise ToolError(f"Unknown tool: {name}")
```

The `ToolError` is then caught by the low-level server's exception handler and converted to `isError: true`.

### Suggested Fixes

#### TypeScript SDK

Move the unknown tool check outside the try block so `McpError` propagates as a protocol error.

#### Python SDK

1. Raise `McpError` with `INVALID_PARAMS` instead of `ToolError` in `tool_manager.py`
2. Add `McpError` exception handler in `server.py` to re-raise it as a protocol error

---

## Issue 2: Streamable HTTP Missing Error Response Handling

### Status: CONFIRMED

### MCP Specification Reference

**Spec URL (line 119-120):** https://github.com/modelcontextprotocol/modelcontextprotocol/blob/c1e0b4d39a630fd87807602c6ace6eefc15154a5/docs/specification/2025-11-25/basic/transports.mdx#L119-L120

> The SSE stream **SHOULD** eventually include a JSON-RPC _response_ for the JSON-RPC _request_ sent in the POST body.

### JSON-RPC 2.0 Specification Reference

**Spec URL:** https://www.jsonrpc.org/specification#response_object

The JSON-RPC 2.0 spec explicitly defines that a Response object contains either `result` (success) or `error` (error):

> "Either the result member or error member MUST be included, but both members MUST NOT be included."

Therefore, when the MCP spec says "JSON-RPC response", it includes both success and error responses. The TypeScript SDK incorrectly only treats success responses as completing the request.

### Problem Description

The TypeScript SDK's `StreamableHTTPClientTransport` only checks for success responses (`isJSONRPCResultResponse`) when handling SSE stream messages. This causes:

1. **Unnecessary reconnection**: The `receivedResponse` flag is not set for error responses
2. **Missing ID remapping**: Error response IDs are not remapped during stream resumption

### Current TypeScript SDK Behavior (WRONG)

**GitHub URL:** https://github.com/modelcontextprotocol/typescript-sdk/blob/5ce4b5ef086045629e1ad444785d2d1fdb137a09/packages/client/src/client/streamableHttp.ts#L364-L368

The code only checks `isJSONRPCResultResponse(message)`:

```typescript
if (isJSONRPCResultResponse(message)) {
    receivedResponse = true;
    if (replayMessageId !== undefined) {
        message.id = replayMessageId;
    }
}
```

Error responses are passed through to `onmessage` but don't set `receivedResponse` or get ID remapping.

### Python SDK Reference Implementation (CORRECT)

**GitHub URL:** https://github.com/modelcontextprotocol/python-sdk/blob/0da9a074d09267a927d72faa58c26d828f0f8edb/src/mcp/client/streamable_http.py#L225-L237

The Python SDK correctly handles BOTH success and error responses:

```python
# If this is a response and we have original_request_id, replace it
if original_request_id is not None and isinstance(message.root, JSONRPCResponse | JSONRPCError):
    message.root.id = original_request_id

# ...

# If this is a response or error return True indicating completion
return isinstance(message.root, JSONRPCResponse | JSONRPCError)
```

### Suggested Fix

Import `isJSONRPCErrorResponse` and handle both response types:

```typescript
if (isJSONRPCResultResponse(message) || isJSONRPCErrorResponse(message)) {
    receivedResponse = true;
    if (replayMessageId !== undefined) {
        message.id = replayMessageId;
    }
}
```

---

## Summary

| Issue | SDK | Severity | Status | Wrong Behavior Location |
|-------|-----|----------|--------|------------------------|
| Unknown tool returns `isError: true` | TypeScript | Medium | Confirmed | [mcp.ts#L179-L232](https://github.com/modelcontextprotocol/typescript-sdk/blob/5ce4b5ef086045629e1ad444785d2d1fdb137a09/packages/server/src/server/mcp.ts#L179-L232) |
| Unknown tool returns `isError: true` | Python | Medium | Confirmed | [tool_manager.py#L89-L91](https://github.com/modelcontextprotocol/python-sdk/blob/0da9a074d09267a927d72faa58c26d828f0f8edb/src/mcp/server/fastmcp/tools/tool_manager.py#L89-L91) |
| Missing error response handling | TypeScript | Medium | Confirmed | [streamableHttp.ts#L364-L368](https://github.com/modelcontextprotocol/typescript-sdk/blob/5ce4b5ef086045629e1ad444785d2d1fdb137a09/packages/client/src/client/streamableHttp.ts#L364-L368) |

### PRs Filed

1. **TypeScript SDK**: Fix unknown tool error handling in `mcp.ts` - https://github.com/modelcontextprotocol/typescript-sdk/pull/1389
2. **TypeScript SDK**: Fix streamable HTTP error response handling in `streamableHttp.ts` - https://github.com/modelcontextprotocol/typescript-sdk/pull/1390
3. **Python SDK**: Fix unknown tool error handling in `tool_manager.py` / `server.py` - https://github.com/modelcontextprotocol/python-sdk/pull/1872

## References

- [MCP Specification - Tools Error Handling](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/c1e0b4d39a630fd87807602c6ace6eefc15154a5/docs/specification/2025-03-26/server/tools.mdx#L244-L287)
- [MCP Specification - Streamable HTTP Transports](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/c1e0b4d39a630fd87807602c6ace6eefc15154a5/docs/specification/2025-11-25/basic/transports.mdx#L119-L120)
- [JSON-RPC 2.0 Specification - Response Object](https://www.jsonrpc.org/specification#response_object)
- [Python SDK correct error response handling](https://github.com/modelcontextprotocol/python-sdk/blob/0da9a074d09267a927d72faa58c26d828f0f8edb/src/mcp/client/streamable_http.py#L225-L237) (reference for TypeScript Issue 2)

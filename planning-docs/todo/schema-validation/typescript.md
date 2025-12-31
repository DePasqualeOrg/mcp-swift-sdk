# Schema Validation in the MCP TypeScript SDK

This document analyzes how schema validation is performed throughout the MCP TypeScript SDK, covering the validation infrastructure, protocol layer, server-side, client-side, and transport layer validation.

## Table of Contents

1. [Validation Infrastructure](#1-validation-infrastructure)
2. [Zod Compatibility Layer](#2-zod-compatibility-layer)
3. [Protocol Layer Validation](#3-protocol-layer-validation)
4. [Transport Layer Validation](#4-transport-layer-validation)
5. [Server-Side Validation](#5-server-side-validation)
6. [Client-Side Validation](#6-client-side-validation)
7. [OAuth Authentication Validation](#7-oauth-authentication-validation)
8. [Validation Flow Summary](#8-validation-flow-summary)

---

## 1. Validation Infrastructure

**Location:** `packages/core/src/validation/`

The SDK provides a pluggable JSON Schema validation system with two built-in providers.

### Type Definitions (`types.ts`)

```typescript
// JSON Schema Draft 2020-12 type
export type JsonSchemaType = JSONSchema.Interface;

// Validation result - discriminated union
export type JsonSchemaValidatorResult<T> =
    | { valid: true; data: T; errorMessage: undefined }
    | { valid: false; data: undefined; errorMessage: string };

// Validator function type
export type JsonSchemaValidator<T> = (input: unknown) => JsonSchemaValidatorResult<T>;

// Provider interface - main extension point
export interface jsonSchemaValidator {
    getValidator<T>(schema: JsonSchemaType): JsonSchemaValidator<T>;
}
```

### AJV Provider (`ajv-provider.ts`)

The default JSON Schema validator using [AJV](https://ajv.js.org/):

```typescript
export class AjvJsonSchemaValidator implements jsonSchemaValidator {
    private _ajv: Ajv;

    constructor(ajv?: Ajv) {
        this._ajv = ajv ?? createDefaultAjvInstance();
    }

    getValidator<T>(schema: JsonSchemaType): JsonSchemaValidator<T> {
        // Cache by $id if available, otherwise compile fresh
        const ajvValidator =
            '$id' in schema && typeof schema.$id === 'string'
                ? (this._ajv.getSchema(schema.$id) ?? this._ajv.compile(schema))
                : this._ajv.compile(schema);

        return (input: unknown): JsonSchemaValidatorResult<T> => {
            const valid = ajvValidator(input);
            if (valid) {
                return { valid: true, data: input as T, errorMessage: undefined };
            } else {
                return { valid: false, data: undefined, errorMessage: this._ajv.errorsText(ajvValidator.errors) };
            }
        };
    }
}
```

**Default AJV configuration:**
- `strict: false` - Lenient mode
- `validateFormats: true` - Validate string formats
- `validateSchema: false` - Don't validate the schema itself
- `allErrors: true` - Report all validation errors

### Cloudflare Worker Provider (`cfworker-provider.ts`)

Edge-runtime compatible validator using [@cfworker/json-schema](https://github.com/cfworker/cfworker):

```typescript
export class CfWorkerJsonSchemaValidator implements jsonSchemaValidator {
    private shortcircuit: boolean;
    private draft: CfWorkerSchemaDraft;

    constructor(options?: { shortcircuit?: boolean; draft?: CfWorkerSchemaDraft }) {
        this.shortcircuit = options?.shortcircuit ?? true;  // Stop on first error
        this.draft = options?.draft ?? '2020-12';
    }

    getValidator<T>(schema: JsonSchemaType): JsonSchemaValidator<T> {
        const validator = new Validator(schema, this.draft, this.shortcircuit);

        return (input: unknown): JsonSchemaValidatorResult<T> => {
            const result = validator.validate(input);
            if (result.valid) {
                return { valid: true, data: input as T, errorMessage: undefined };
            } else {
                return {
                    valid: false,
                    data: undefined,
                    errorMessage: result.errors.map(err => `${err.instanceLocation}: ${err.error}`).join('; ')
                };
            }
        };
    }
}
```

**Key differences from AJV:**
- No code generation (uses `eval`-free validation)
- Compatible with Cloudflare Workers and other restricted runtimes
- Validators are not cached internally

---

## 2. Zod Compatibility Layer

**Location:** `packages/core/src/util/`

The SDK supports both Zod v3 and Zod v4 (Mini) through a compatibility layer.

### Core Utilities (`zod-compat.ts`)

#### Version Detection

```typescript
export function isZ4Schema(s: AnySchema): s is z4.$ZodType {
    const schema = s as unknown as ZodV4Internal;
    return !!schema._zod;  // v4 has _zod property, v3 has _def
}
```

#### Unified Parsing

```typescript
export function safeParse<S extends AnySchema>(
    schema: S,
    data: unknown
): { success: true; data: SchemaOutput<S> } | { success: false; error: unknown } {
    if (isZ4Schema(schema)) {
        return z4mini.safeParse(schema, data);
    }
    const v3Schema = schema as z3.ZodTypeAny;
    return v3Schema.safeParse(data);
}

export async function safeParseAsync<S extends AnySchema>(
    schema: S,
    data: unknown
): Promise<{ success: true; data: SchemaOutput<S> } | { success: false; error: unknown }> {
    if (isZ4Schema(schema)) {
        return await z4mini.safeParseAsync(schema, data);
    }
    return await (schema as z3.ZodTypeAny).safeParseAsync(data);
}
```

#### Error Message Extraction

```typescript
export function getParseErrorMessage(error: unknown): string {
    if (error && typeof error === 'object') {
        if ('message' in error && typeof error.message === 'string') {
            return error.message;
        }
        if ('issues' in error && Array.isArray(error.issues) && error.issues.length > 0) {
            const firstIssue = error.issues[0];
            if (firstIssue?.message) {
                return String(firstIssue.message);
            }
        }
        try {
            return JSON.stringify(error);
        } catch {
            return String(error);
        }
    }
    return String(error);
}
```

### JSON Schema Conversion (`zod-json-schema-compat.ts`)

#### Schema to JSON Schema

```typescript
export function toJsonSchemaCompat(schema: AnyObjectSchema, opts?: CommonOpts): JsonSchema {
    if (isZ4Schema(schema)) {
        return z4mini.toJSONSchema(schema as z4c.$ZodType, {
            target: mapMiniTarget(opts?.target),
            io: opts?.pipeStrategy ?? 'input'
        });
    }
    return zodToJsonSchema(schema as z3.ZodTypeAny, {
        strictUnions: opts?.strictUnions ?? true,
        pipeStrategy: opts?.pipeStrategy ?? 'input'
    });
}
```

#### Parse with Exception

```typescript
export function parseWithCompat(schema: AnySchema, data: unknown): unknown {
    const result = safeParse(schema, data);
    if (!result.success) {
        throw result.error;
    }
    return result.data;
}
```

---

## 3. Protocol Layer Validation

**Location:** `packages/core/src/shared/protocol.ts`

The abstract `Protocol` class handles message routing and validation for both Client and Server.

### Request Handler Registration

When a request handler is registered, it wraps the handler with validation:

```typescript
setRequestHandler<T extends AnyObjectSchema>(
    requestSchema: T,
    handler: (request: SchemaOutput<T>, extra) => SendResultT | Promise<SendResultT>
): void {
    const method = getMethodLiteral(requestSchema);  // Extract method name from schema
    this.assertRequestHandlerCapability(method);     // Check local capabilities

    this._requestHandlers.set(method, (request, extra) => {
        // Validate incoming request against schema
        const parsed = parseWithCompat(requestSchema, request) as SchemaOutput<T>;
        return Promise.resolve(handler(parsed, extra));
    });
}
```

**Validation flow:**
1. Extract method literal from schema's `method` field
2. Assert handler capability is declared
3. On incoming request: `parseWithCompat()` validates against Zod schema
4. If validation fails: exception is thrown
5. If validation passes: typed data passed to handler

### Notification Handler Registration

Same pattern for notifications:

```typescript
setNotificationHandler<T extends AnyObjectSchema>(
    notificationSchema: T,
    handler: (notification: SchemaOutput<T>) => void | Promise<void>
): void {
    const method = getMethodLiteral(notificationSchema);
    this._notificationHandlers.set(method, notification => {
        const parsed = parseWithCompat(notificationSchema, notification) as SchemaOutput<T>;
        return Promise.resolve(handler(parsed));
    });
}
```

### Response Validation

When sending a request, the response is validated against the expected schema:

```typescript
// In Protocol.request()
this._responseHandlers.set(messageId, response => {
    try {
        const parseResult = safeParse(resultSchema, response.result);
        if (!parseResult.success) {
            reject(parseResult.error);
        } else {
            resolve(parseResult.data as SchemaOutput<T>);
        }
    } catch (error) {
        reject(error);
    }
});
```

---

## 4. Transport Layer Validation

### Message Routing Type Guards

**Location:** `packages/core/src/types/types.ts`

Type guards validate incoming JSON-RPC messages using Zod:

```typescript
export const isJSONRPCRequest = (value: unknown): value is JSONRPCRequest =>
    JSONRPCRequestSchema.safeParse(value).success;

export const isJSONRPCNotification = (value: unknown): value is JSONRPCNotification =>
    JSONRPCNotificationSchema.safeParse(value).success;

export const isJSONRPCResultResponse = (value: unknown): value is JSONRPCResultResponse =>
    JSONRPCResultResponseSchema.safeParse(value).success;

export const isJSONRPCErrorResponse = (value: unknown): value is JSONRPCErrorResponse =>
    JSONRPCErrorResponseSchema.safeParse(value).success;
```

### Transport Message Parsing

#### stdio Transport (`packages/core/src/shared/stdio.ts`)

```typescript
export function deserializeMessage(line: string): JSONRPCMessage {
    return JSONRPCMessageSchema.parse(JSON.parse(line));
}
```

#### Streamable HTTP Client (`packages/client/src/client/streamableHttp.ts`)

```typescript
// SSE message parsing
const message = JSONRPCMessageSchema.parse(JSON.parse(event.data));

// HTTP response parsing
const data = await response.json();
const responseMessages = Array.isArray(data)
    ? data.map(msg => JSONRPCMessageSchema.parse(msg))
    : [JSONRPCMessageSchema.parse(data)];
```

#### Streamable HTTP Server (`packages/server/src/server/webStandardStreamableHttp.ts`)

```typescript
try {
    if (Array.isArray(rawMessage)) {
        messages = rawMessage.map(msg => JSONRPCMessageSchema.parse(msg));
    } else {
        messages = [JSONRPCMessageSchema.parse(rawMessage)];
    }
} catch {
    return this.createJsonErrorResponse(400, -32700, 'Parse error: Invalid JSON-RPC message');
}
```

---

## 5. Server-Side Validation

**Location:** `packages/server/src/server/`

### Server Class (`server.ts`)

#### Configuration

```typescript
export type ServerOptions = ProtocolOptions & {
    jsonSchemaValidator?: jsonSchemaValidator;  // Custom validator provider
    // ...
};

constructor(private _serverInfo: Implementation, options?: ServerOptions) {
    this._jsonSchemaValidator = options?.jsonSchemaValidator ?? new AjvJsonSchemaValidator();
}
```

#### Tools/Call Request Validation

The Server class wraps `tools/call` handlers with additional validation:

```typescript
if (method === 'tools/call') {
    const wrappedHandler = async (request, extra) => {
        // 1. Validate incoming request
        const validatedRequest = safeParse(CallToolRequestSchema, request);
        if (!validatedRequest.success) {
            throw new McpError(ErrorCode.InvalidParams, `Invalid tools/call request: ${errorMessage}`);
        }

        const result = await Promise.resolve(handler(request, extra));

        // 2. Validate outgoing result based on request type
        if (params.task) {
            const taskValidationResult = safeParse(CreateTaskResultSchema, result);
            if (!taskValidationResult.success) {
                throw new McpError(ErrorCode.InvalidParams, `Invalid task creation result: ${errorMessage}`);
            }
            return taskValidationResult.data;
        } else {
            const validationResult = safeParse(CallToolResultSchema, result);
            if (!validationResult.success) {
                throw new McpError(ErrorCode.InvalidParams, `Invalid tools/call result: ${errorMessage}`);
            }
            return validationResult.data;
        }
    };
}
```

#### Elicitation Response Validation

When the server receives an elicitation response, it validates against the requested schema:

```typescript
const result = await this.request({ method: 'elicitation/create', params: formParams }, ElicitResultSchema, options);

if (result.action === 'accept' && result.content && formParams.requestedSchema) {
    const validator = this._jsonSchemaValidator.getValidator(formParams.requestedSchema as JsonSchemaType);
    const validationResult = validator(result.content);

    if (!validationResult.valid) {
        throw new McpError(
            ErrorCode.InvalidParams,
            `Elicitation response content does not match requested schema: ${validationResult.errorMessage}`
        );
    }
}
```

### McpServer Class (`mcp.ts`)

#### Tool Input Validation

```typescript
private async validateToolInput<Args>(tool: Tool, args: Args, toolName: string): Promise<Args> {
    if (!tool.inputSchema) {
        return undefined as Args;
    }

    const inputObj = normalizeObjectSchema(tool.inputSchema);
    const schemaToParse = inputObj ?? (tool.inputSchema as AnySchema);
    const parseResult = await safeParseAsync(schemaToParse, args);

    if (!parseResult.success) {
        const errorMessage = getParseErrorMessage(parseResult.error);
        throw new McpError(
            ErrorCode.InvalidParams,
            `Input validation error: Invalid arguments for tool ${toolName}: ${errorMessage}`
        );
    }

    return parseResult.data as Args;
}
```

#### Tool Output Validation

```typescript
private async validateToolOutput(tool: RegisteredTool, result: CallToolResult | CreateTaskResult, toolName: string): Promise<void> {
    if (!tool.outputSchema) return;
    if (!('content' in result)) return;  // Skip CreateTaskResult
    if (result.isError) return;          // Skip error results

    if (!result.structuredContent) {
        throw new McpError(
            ErrorCode.InvalidParams,
            `Output validation error: Tool ${toolName} has an output schema but no structured content was provided`
        );
    }

    const outputObj = normalizeObjectSchema(tool.outputSchema) as AnyObjectSchema;
    const parseResult = await safeParseAsync(outputObj, result.structuredContent);

    if (!parseResult.success) {
        const errorMessage = getParseErrorMessage(parseResult.error);
        throw new McpError(
            ErrorCode.InvalidParams,
            `Output validation error: Invalid structured content for tool ${toolName}: ${errorMessage}`
        );
    }
}
```

#### Prompt Argument Validation

```typescript
if (prompt.argsSchema) {
    const argsObj = normalizeObjectSchema(prompt.argsSchema) as AnyObjectSchema;
    const parseResult = await safeParseAsync(argsObj, request.params.arguments);

    if (!parseResult.success) {
        const errorMessage = getParseErrorMessage(parseResult.error);
        throw new McpError(
            ErrorCode.InvalidParams,
            `Invalid arguments for prompt ${request.params.name}: ${errorMessage}`
        );
    }

    const args = parseResult.data;
    return await Promise.resolve(callback(args, extra));
}
```

---

## 6. Client-Side Validation

**Location:** `packages/client/src/client/client.ts`

### Configuration

```typescript
export type ClientOptions = ProtocolOptions & {
    jsonSchemaValidator?: jsonSchemaValidator;
    // ...
};

constructor(private _clientInfo: Implementation, options?: ClientOptions) {
    this._jsonSchemaValidator = options?.jsonSchemaValidator ?? new AjvJsonSchemaValidator();
}
```

### Elicitation Request Handler Validation

```typescript
if (method === 'elicitation/create') {
    const wrappedHandler = async (request, extra) => {
        // 1. Validate incoming request
        const validatedRequest = safeParse(ElicitRequestSchema, request);
        if (!validatedRequest.success) {
            throw new McpError(ErrorCode.InvalidParams, `Invalid elicitation request: ${errorMessage}`);
        }

        const result = await Promise.resolve(handler(request, extra));

        // 2. Validate outgoing result
        if (params.task) {
            const taskValidationResult = safeParse(CreateTaskResultSchema, result);
            // ...
        } else {
            const validationResult = safeParse(ElicitResultSchema, result);
            // ...
        }

        // 3. Apply defaults if configured
        if (params.mode === 'form' && validatedResult.action === 'accept' && requestedSchema) {
            if (this._capabilities.elicitation?.form?.applyDefaults) {
                applyElicitationDefaults(requestedSchema, validatedResult.content);
            }
        }

        return validatedResult;
    };
}
```

### Sampling Request Handler Validation

```typescript
if (method === 'sampling/createMessage') {
    const wrappedHandler = async (request, extra) => {
        // 1. Validate incoming request
        const validatedRequest = safeParse(CreateMessageRequestSchema, request);
        if (!validatedRequest.success) {
            throw new McpError(ErrorCode.InvalidParams, `Invalid sampling request: ${errorMessage}`);
        }

        const result = await Promise.resolve(handler(request, extra));

        // 2. Validate outgoing result
        if (params.task) {
            const taskValidationResult = safeParse(CreateTaskResultSchema, result);
            // ...
        } else {
            const validationResult = safeParse(CreateMessageResultSchema, result);
            // ...
        }
    };
}
```

### Tool Output Schema Caching

The client pre-compiles validators for tool output schemas:

```typescript
private cacheToolMetadata(tools: Tool[]): void {
    this._cachedToolOutputValidators.clear();

    for (const tool of tools) {
        if (tool.outputSchema) {
            const toolValidator = this._jsonSchemaValidator.getValidator(tool.outputSchema as JsonSchemaType);
            this._cachedToolOutputValidators.set(tool.name, toolValidator);
        }
    }
}

async listTools(params?, options?) {
    const result = await this.request({ method: 'tools/list', params }, ListToolsResultSchema, options);
    this.cacheToolMetadata(result.tools);  // Pre-compile validators
    return result;
}
```

### List Changed Options Validation

```typescript
const parseResult = ListChangedOptionsBaseSchema.safeParse(options);
if (!parseResult.success) {
    throw new Error(`Invalid ${listType} listChanged options: ${parseResult.error.message}`);
}
```

### Elicitation Defaults Application

Recursively applies defaults from JSON Schema to response data:

```typescript
function applyElicitationDefaults(schema: JsonSchemaType | undefined, data: unknown): void {
    if (!schema || data === null || typeof data !== 'object') return;

    if (schema.type === 'object' && schema.properties) {
        const obj = data as Record<string, unknown>;
        const props = schema.properties as Record<string, JsonSchemaType & { default?: unknown }>;

        for (const key of Object.keys(props)) {
            const propSchema = props[key]!;
            // Apply default if property is undefined
            if (obj[key] === undefined && Object.prototype.hasOwnProperty.call(propSchema, 'default')) {
                obj[key] = propSchema.default;
            }
            // Recurse into nested objects
            if (obj[key] !== undefined) {
                applyElicitationDefaults(propSchema, obj[key]);
            }
        }
    }

    // Handle anyOf/oneOf combinations
    if (Array.isArray(schema.anyOf)) {
        for (const sub of schema.anyOf) {
            if (typeof sub !== 'boolean') {
                applyElicitationDefaults(sub, data);
            }
        }
    }
}
```

---

## 7. OAuth Authentication Validation

**Location:** `packages/server/src/server/auth/handlers/`

OAuth endpoints use Zod validation for request parameters.

### Token Endpoint (`token.ts`)

```typescript
// Validate grant type
const parseResult = TokenRequestSchema.safeParse(req.body);
if (!parseResult.success) {
    throw new InvalidRequestError(parseResult.error.message);
}

switch (grant_type) {
    case 'authorization_code': {
        const parseResult = AuthorizationCodeGrantSchema.safeParse(req.body);
        if (!parseResult.success) {
            throw new InvalidRequestError(parseResult.error.message);
        }
        // ...
    }
    case 'refresh_token': {
        const parseResult = RefreshTokenGrantSchema.safeParse(req.body);
        if (!parseResult.success) {
            throw new InvalidRequestError(parseResult.error.message);
        }
        // ...
    }
}
```

### Authorization Endpoint (`authorize.ts`)

```typescript
// Validate client authorization params
const result = ClientAuthorizationParamsSchema.safeParse(req.method === 'POST' ? req.body : req.query);

// Validate request authorization params
const parseResult = RequestAuthorizationParamsSchema.safeParse(req.method === 'POST' ? req.body : req.query);
```

### Revoke Endpoint (`revoke.ts`)

```typescript
const parseResult = OAuthTokenRevocationRequestSchema.safeParse(req.body);
if (!parseResult.success) {
    throw new InvalidRequestError(parseResult.error.message);
}
```

### Register Endpoint (`register.ts`)

```typescript
const parseResult = OAuthClientMetadataSchema.safeParse(req.body);
if (!parseResult.success) {
    throw new InvalidClientMetadataError(parseResult.error.message);
}
```

### Client Authentication Middleware (`clientAuth.ts`)

```typescript
const result = ClientAuthenticatedRequestSchema.safeParse(req.body);
```

---

## 8. Validation Flow Summary

### Incoming Request Flow

```
Transport receives raw data
    ↓
JSON.parse() + JSONRPCMessageSchema.parse()  (Transport layer)
    ↓
isJSONRPCRequest() / isJSONRPCNotification() type guards  (Message routing)
    ↓
parseWithCompat(requestSchema, rawMessage)  (Protocol layer)
    ↓
safeParse() for additional validation  (Server/Client layer)
    ↓
Handler receives typed, validated data
```

### Outgoing Response Flow

```
Handler returns result
    ↓
safeParse() validates result  (Server/Client layer - for specific methods)
    ↓
Transport.send()
```

### Validation by Layer

| Layer | Technology | Validation Type |
|-------|-----------|-----------------|
| Transport | Zod | JSON-RPC message structure |
| Protocol | Zod | Request/notification schemas |
| Server | Zod + JSON Schema | Tool I/O, elicitation responses |
| Client | Zod + JSON Schema | Sampling/elicitation handlers, tool output caching |
| OAuth | Zod | Request parameters |

### Error Handling

All validation failures produce `McpError` with:
- **Code:** `ErrorCode.InvalidParams` (typically)
- **Message:** Description of validation failure
- **Data:** Optional error details

Errors are converted to JSON-RPC error responses and sent back to the remote side.

### Configuration

Both Client and Server accept a `jsonSchemaValidator` option:

```typescript
// Use default (AJV)
const server = new Server(serverInfo);

// Use custom validator for edge runtimes
const server = new Server(serverInfo, {
    jsonSchemaValidator: new CfWorkerJsonSchemaValidator()
});
```

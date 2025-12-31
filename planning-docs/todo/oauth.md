# Auth Implementation Analysis for MCP Swift SDK

Analysis of authentication requirements and available Swift ecosystem tools for implementing OAuth 2.0 support in the MCP Swift SDK.

## MCP Spec Requirements

The MCP specification defines authorization requirements by transport type:

| Transport | Requirement |
|-----------|-------------|
| HTTP-based | **SHOULD** use OAuth 2.1 per the spec |
| STDIO | **SHOULD NOT** use OAuth; retrieve credentials from environment |
| Other | **MUST** follow established security best practices |

The spec mandates OAuth 2.1 with PKCE, RFC 8414 (AS Metadata), RFC 9728 (Protected Resource Metadata), and RFC 8707 (Resource Indicators).

See: [MCP Authorization Specification](https://modelcontextprotocol.io/specification/draft/basic/authorization)

### What the SDK Handles vs. Application Code

The MCP SDK is responsible for:
- **MCP client → MCP server auth**: OAuth 2.1 flow per the spec

The SDK is **not** responsible for:
- **MCP server → upstream APIs**: If your MCP server calls OpenAI, GitHub, or other services, that's application code. You handle those credentials however you want (environment variables, keychain, etc.) using standard HTTP clients.

Simple bearer tokens and API keys for upstream services are the server application's responsibility, not the SDK's.

## Current State

The Swift SDK has **foundational auth infrastructure** but no OAuth flow implementation yet. Both the TypeScript and Python SDKs have comprehensive OAuth 2.0 support (~3,300 lines each).

**What's already implemented:**

| Component | Location | Status |
|-----------|----------|--------|
| `AuthInfo` struct | `HTTPServerTransport+Types.swift` | Complete - OAuth2-ready with scopes, expiration, resource |
| `OAuthTokens` struct | `Transports/OAuth.swift` | Complete - matches RFC 6749 token response |
| `OAuthClientProvider` protocol | `Transports/OAuth.swift` | Complete - tokens(), handleUnauthorized(context:) |
| `UnauthorizedContext` struct | `Transports/OAuth.swift` | Complete - 401 response context for OAuth flow |
| `authProvider` parameter | `HTTPClientTransport.swift` | Complete - reserved for OAuth, not yet wired up |
| `requestModifier` pattern | `HTTPClientTransport.swift` | Complete - works for simple Bearer token injection |
| `handleRequest(_:authInfo:)` | `HTTPServerTransport.swift` | Complete - accepts auth context from middleware |
| `context.authInfo` | `Server.RequestHandlerContext` | Complete - available in request handlers |

**What still needs to be built:**
- OAuth flow implementation (discovery, authorization, token exchange)
- Transport integration (401 handling, automatic token refresh)
- Client authentication methods (basic, post, jwt)
- Server-side OAuth endpoints (optional)

## Scope Comparison

| SDK | Lines of Auth Code |
|-----|-------------------|
| TypeScript | ~3,332 |
| Python | ~3,334 |
| Swift (needed) | ~2,200-3,300 |

**Note:** Both TypeScript and Python already use external libraries for crypto primitives:
- TypeScript: `pkce-challenge` for PKCE, Web Crypto API for hashing
- Python: `jwt` (PyJWT) for JWT, stdlib `hashlib`/`secrets` for PKCE

The ~3,300 lines in each SDK is OAuth **protocol** code (flows, endpoints, metadata discovery, token management, error handling), not crypto implementations. Swift will similarly use libraries (jwt-kit, CryptoKit) but will still need comparable protocol code.

## What the TS/Python SDKs Implement

Both SDKs implement the MCP spec's OAuth 2.1 requirements. They do **not** provide first-class support for simple bearer tokens or API keys - users must pass custom headers manually.

### Client-Side Auth
- OAuth 2.0 Authorization Code flow with PKCE (RFC 7636)
- Client Credentials grant (machine-to-machine)
- Private Key JWT authentication (`private_key_jwt`)
- Token refresh and revocation
- Metadata discovery (RFC 8414, RFC 9728)
- Dynamic client registration (RFC 7591)
- Resource indicators (RFC 8707)
- WWW-Authenticate header parsing
- Scope step-up handling

### Server-Side Auth
- Authorization endpoint with PKCE enforcement
- Token endpoint (authorization_code, refresh_token, client_credentials grants)
- Registration endpoint (RFC 7591)
- Metadata endpoints (RFC 8414, RFC 9728)
- Token revocation endpoint (RFC 7009)
- Bearer token validation middleware
- Client authentication methods (`client_secret_basic`, `client_secret_post`, `none`)

### Client Authentication Methods
| Method | Description |
|--------|-------------|
| `client_secret_basic` | HTTP Basic auth with client_id:client_secret |
| `client_secret_post` | Credentials in request body |
| `none` | Public clients (no secret) |
| `private_key_jwt` | JWT signed with private key |

## Available Swift Ecosystem Tools

### JWT Operations

**[jwt-kit](https://github.com/vapor/jwt-kit)** (Vapor project, v5.0.0+)
- Full JWT signing and verification
- Supports: HMAC, ECDSA, EdDSA, MLDSA, RSA, PSS
- JWS and JWK support
- Depends on swift-crypto
- **Recommended for MCP Swift SDK**

**[Swift-JWT](https://github.com/Kitura/Swift-JWT)** (IBM Kitura)
- Alternative JWT library
- Less actively maintained than jwt-kit

**[JWTDecode.swift](https://github.com/auth0/JWTDecode.swift)** (Auth0)
- Decode only, no verification
- Useful for inspecting tokens without validation

**[JOSESwift](https://swiftpackageregistry.com/airsidemobile/JOSESwift)**
- Full JOSE standards (JWS, JWE, JWK)
- Uses Apple Security framework and CryptoKit

### PKCE

**[swift-pkce](https://swiftpackageregistry.com/hendrickson-tyler/swift-pkce)**
- Lightweight RFC 7636 implementation
- Code verifier and S256 challenge generation
- Requires iOS 13.0+, macOS 10.15+

**CryptoKit (built-in)**
- PKCE S256 is just SHA256 + base64url encoding
- No external dependency needed
- Available on all Apple platforms

### Hummingbird Auth

**[hummingbird-auth](https://github.com/hummingbird-project/hummingbird-auth)** (v2.0.0+)

| Module | Purpose |
|--------|---------|
| `HummingbirdAuth` | Core middleware, `AuthenticatorMiddleware` protocol |
| `HummingbirdBasicAuth` | Basic HTTP auth extraction |
| `HummingbirdBcrypt` | Password hashing |
| `HummingbirdOTP` | One-time passwords |

**What it provides:**
- Bearer token extraction (`request.headers.bearer`)
- Basic auth extraction (`request.headers.basic`)
- `AuthenticatorMiddleware` protocol for custom authenticators
- Session management patterns

**What it does NOT provide:**
- OAuth server endpoints
- OAuth client flows
- PKCE implementation
- Metadata discovery
- Token storage

### Client-Side OAuth Libraries

**[OAuthSwift](https://github.com/OAuthSwift/OAuthSwift)**
- Client-side OAuth 1.0/2.0
- iOS focused
- Handles authorization flows and token management
- May be too opinionated for MCP's needs

## What Libraries Provide vs What Must Be Built

### Libraries Handle (same as TS/Python)

| Component | Swift Library | TS/Python Equivalent |
|-----------|---------------|---------------------|
| JWT signing/verification | jwt-kit | PyJWT / N/A |
| PKCE S256 challenge | CryptoKit | hashlib / pkce-challenge |
| Bearer token extraction | hummingbird-auth | manual |
| HTTP Basic auth encoding | Foundation | btoa / base64 |

**Important:** These libraries don't reduce total LOC compared to TS/Python - those SDKs already use equivalent libraries and still need ~3,300 lines of protocol code.

### Must Build (OAuth Protocol Code)

| Component | Estimated LOC | Notes |
|-----------|---------------|-------|
| OAuth types and schemas | ~150-250 | Metadata, errors, client info (OAuthTokens, UnauthorizedContext done) |
| OAuth provider implementations | ~300-400 | DefaultOAuthProvider, ClientCredentialsProvider, etc. |
| Authorization code flow | ~300-400 | PKCE, redirect handling, state |
| Client credentials flow | ~150-200 | M2M authentication |
| Private key JWT auth | ~150-200 | JWT assertion for client auth |
| Token refresh logic | ~100-150 | Automatic refresh on expiry/401 |
| Metadata discovery | ~300-400 | RFC 8414, RFC 9728, OIDC fallback |
| Client authentication methods | ~150-200 | basic, post, none selection logic |
| WWW-Authenticate parsing | ~50-100 | Extract resource_metadata, scope, error |
| Error handling | ~100-150 | OAuth error types and parsing |
| Transport integration | ~200-300 | Wire auth into HTTP client |
| **Client subtotal** | **~1,850-2,600** | |
| Server endpoints (optional) | ~600-800 | Authorization, token, register, revoke |
| **Full implementation** | **~2,450-3,400** | |

## Recommended Dependencies

```swift
// Package.swift additions
.package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),

// Only if building OAuth server transport
.package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),
```

**Note:** jwt-kit brings in swift-crypto (~3.4.0) and swift-certificates (~1.4.0) as transitive dependencies.

**Alternative worth investigating:** Python has [Authlib](https://github.com/authlib/authlib) which implements most OAuth RFCs (6749, 7636, 7591, 7009, 7523). The MCP SDKs chose not to use it, possibly due to dependency philosophy or needing RFC 9728 support. A Swift equivalent could significantly reduce implementation effort if one exists and covers MCP's requirements.

## Phased Implementation Approach

### Phase 1: OAuth Client Basics

Interactive OAuth 2.0 with PKCE for user-facing applications.

**Use cases:**
- CLI tools that need user login
- Desktop/mobile apps authenticating users
- Any interactive MCP client

**Components:**
| Component | LOC | Description |
|-----------|-----|-------------|
| ~~OAuthClientProvider protocol~~ | ~~done~~ | ~~Already exists in OAuth.swift~~ |
| ~~OAuthTokens, UnauthorizedContext~~ | ~~done~~ | ~~Already exists in OAuth.swift~~ |
| OAuth metadata types | ~100 | Server metadata, client info, protected resource metadata |
| PKCE implementation | ~50 | S256 challenge/verifier (CryptoKit) |
| DefaultOAuthProvider | ~250 | Main provider implementation with full flow |
| Token storage protocol | ~50 | Abstract storage interface |
| In-memory token storage | ~30 | Simple implementation |
| Token refresh | ~100 | Automatic refresh on expiry/401 |
| Metadata discovery | ~200 | RFC 8414, OIDC fallback (see TS buildDiscoveryUrls) |
| Client auth methods | ~100 | basic, post, none selection |
| Error handling | ~100 | OAuth error parsing (see TS parseErrorResponse) |
| Transport integration | ~150 | Wire authProvider into HTTPClientTransport |
| **Total** | **~1,130** | (reduced - protocol/types done) |

**Reality check:** TS `auth.ts` alone is 1,300 lines and doesn't include types or extensions.

**Dependencies:** jwt-kit (for token parsing/validation)

**Example API (target):**
```swift
// Create an OAuth provider (implementation to be built)
let oauthProvider = DefaultOAuthProvider(
    clientId: "my-client",
    redirectURL: redirectURL,
    tokenStorage: InMemoryTokenStorage(),
    redirectHandler: { url in /* open browser */ },
    callbackHandler: { /* receive auth code */ }
)

// Pass to transport via authProvider parameter (already exists)
let transport = HTTPClientTransport(
    endpoint: serverURL,
    authProvider: oauthProvider
)

// Provider handles:
// - Metadata discovery (RFC 8414, 9728)
// - Opening browser for auth
// - PKCE challenge/verifier
// - Token exchange
// - Automatic refresh on 401

// Alternative: Simple bearer token via requestModifier (works today)
let transport = HTTPClientTransport(
    endpoint: serverURL,
    requestModifier: { request in
        var r = request
        r.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
)
```

---

### Phase 2: Advanced Client Auth

Machine-to-machine and enterprise authentication patterns.

**Use cases:**
- Server-to-server MCP communication
- CI/CD pipelines
- Enterprise SSO integration

**Components:**
| Component | LOC | Description |
|-----------|-----|-------------|
| Client credentials provider | ~200 | Full provider impl (see Python ClientCredentialsOAuthProvider) |
| Private key JWT provider | ~250 | `private_key_jwt` with jwt-kit (see Python PrivateKeyJWTOAuthProvider) |
| Protected resource metadata | ~150 | RFC 9728 discovery |
| WWW-Authenticate parsing | ~80 | Extract resource_metadata, scope, error |
| Keychain token storage | ~100 | Secure Apple platforms storage |
| Resource indicators | ~50 | RFC 8707 support |
| **Total** | **~830** | |

**Reality check:** Python's `client_credentials.py` alone is 487 lines.

**Dependencies:** Phase 1

**Example API:**
```swift
// Client credentials (M2M)
let provider = ClientCredentialsProvider(
    clientId: "service-client",
    clientSecret: "secret",
    tokenURL: tokenURL,
    scopes: ["mcp:read", "mcp:write"]
)

// Private key JWT
let provider = PrivateKeyJWTProvider(
    clientId: "enterprise-client",
    privateKey: privateKey,
    tokenURL: tokenURL
)
```

---

### Phase 3: Server-Side Auth (Optional)

OAuth server capabilities for HTTP server transport.

**Use cases:**
- MCP servers that need to authenticate clients
- Servers that issue their own tokens
- Full OAuth provider implementation

**Components:**
| Component | LOC | Description |
|-----------|-----|-------------|
| Server provider protocol | ~100 | Abstract OAuth server interface |
| Authorization endpoint | ~200 | With PKCE validation (see TS authorize.ts: 167 lines) |
| Token endpoint | ~250 | Multiple grant types (see TS token.ts: 158 lines) |
| Registration endpoint | ~130 | RFC 7591 (see TS register.ts: 129 lines) |
| Metadata endpoint | ~50 | RFC 8414 |
| Revocation endpoint | ~90 | RFC 7009 (see TS revoke.ts: 87 lines) |
| Bearer middleware | ~130 | Token validation (see TS bearerAuth.ts: 103 lines) |
| Client auth middleware | ~80 | Validate client credentials |
| Router/routes | ~150 | Wire endpoints together |
| **Total** | **~1,180** | |

**Reality check:** TS server auth (`packages/server/src/server/auth/`) is 1,344 lines. Python's is 1,620 lines.

**Dependencies:** Phase 1-2 + hummingbird-auth (for middleware patterns)

---

## Summary

| Phase | Scope | LOC | Cumulative |
|-------|-------|-----|------------|
| 1 | OAuth client basics | ~1,130 | ~1,130 |
| 2 | Advanced client auth | ~830 | ~1,960 |
| 3 | Server-side auth | ~1,180 | ~3,140 |

*LOC reduced from original estimates - foundational types (OAuthTokens, UnauthorizedContext, OAuthClientProvider protocol) already implemented.*

**Recommendation:** Start with Phase 1 for core OAuth support (required by spec). Phase 2 adds M2M auth patterns. Phase 3 (server-side) can be deferred based on demand.

**Reality check:**
- TypeScript total: ~3,332 lines (client: ~1,988, server: ~1,344)
- Python total: ~3,334 lines (client: ~1,714, server: ~1,620)
- Swift estimate: ~3,340 lines (aligns with TS/Python)

## File Structure

```
Sources/MCP/
├── Base/
│   └── Transports/
│       ├── OAuth.swift                    # [EXISTS] OAuthTokens, UnauthorizedContext, OAuthClientProvider
│       ├── HTTPClientTransport.swift      # [EXISTS] Has authProvider parameter
│       └── HTTPServerTransport+Types.swift # [EXISTS] AuthInfo struct
├── Auth/                                  # [TO BUILD]
│   ├── OAuth/
│   │   ├── PKCE.swift                     # PKCE challenge/verifier (CryptoKit)
│   │   ├── AuthorizationCodeFlow.swift    # Full auth code flow
│   │   ├── ClientCredentialsFlow.swift    # M2M flow
│   │   ├── MetadataDiscovery.swift        # RFC 8414, 9728 discovery
│   │   └── OAuthErrors.swift              # OAuth error types
│   ├── TokenStorage/
│   │   ├── TokenStorage.swift             # Protocol
│   │   └── KeychainTokenStorage.swift     # Apple platforms
│   ├── Client/
│   │   ├── DefaultOAuthProvider.swift     # Main implementation
│   │   └── ClientAuthentication.swift     # basic, post, none, jwt
│   └── Server/                            # Optional
│       ├── OAuthServerProvider.swift      # Server provider protocol
│       ├── AuthorizationHandler.swift
│       ├── TokenHandler.swift
│       ├── RegistrationHandler.swift
│       └── BearerMiddleware.swift
```

## Implementation Notes from TS/Python Analysis

### OAuth Flow Sequence (Client)

The MCP OAuth flow follows this sequence:

1. **Client sends request** → Server returns 401 with `WWW-Authenticate` header
2. **Extract resource_metadata URL** from `WWW-Authenticate` header
3. **Fetch Protected Resource Metadata** (RFC 9728) from `/.well-known/oauth-protected-resource`
4. **Fetch Authorization Server Metadata** (RFC 8414) with fallback chain:
   - `/.well-known/oauth-authorization-server{path}` (RFC 8414)
   - `/.well-known/openid-configuration{path}` (OIDC)
   - `{path}/.well-known/openid-configuration` (OIDC legacy)
5. **Client registration** via one of:
   - Pre-registered credentials
   - URL-based Client ID (client hosts metadata at HTTPS URL)
   - Dynamic Client Registration (RFC 7591)
6. **Authorization request** with PKCE (S256 code challenge)
7. **Token exchange** with code_verifier and resource parameter (RFC 8707)
8. **Authenticated requests** with `Authorization: Bearer {token}`

### Key Spec Requirements

- **PKCE is mandatory** - All authorization code flows must use S256
- **Resource indicators** (RFC 8707) - Tokens are bound to specific MCP servers via `resource` parameter
- **Scope selection** - Use scope from WWW-Authenticate, fall back to `scopes_supported` from metadata
- **Token refresh** - Attempt refresh before expiry, handle 401 by triggering `handleUnauthorized()`

### Client ID Metadata Documents (Alternative to DCR)

The spec supports URL-based client IDs where the client hosts its metadata at an HTTPS URL:
```json
{
  "client_id": "https://app.example.com/oauth/client-metadata.json",
  "client_name": "My MCP Client",
  "redirect_uris": ["http://127.0.0.1:3000/callback"],
  "grant_types": ["authorization_code"],
  "token_endpoint_auth_method": "none"
}
```

The auth server fetches and validates this document. Check `client_id_metadata_document_supported` in server metadata.

### Error Handling

Both TS and Python define comprehensive OAuth error types:
- `InvalidRequestError`, `InvalidClientError`, `InvalidGrantError`
- `UnauthorizedClientError`, `UnsupportedGrantTypeError`, `InvalidScopeError`
- `AccessDeniedError`, `ServerError`, `TemporarilyUnavailableError`
- `InvalidTokenError`, `InsufficientScopeError`, `InvalidTargetError` (RFC 8707)

## Key Design Decisions

### 1. Token Storage
- Define a `TokenStorage` protocol for flexibility
- Provide `KeychainTokenStorage` for Apple platforms
- Allow custom implementations (in-memory, file-based, etc.)

### 2. Transport Integration
- Auth is composable with transports via two mechanisms:
  - `requestModifier`: Simple closure for static tokens, API keys
  - `authProvider`: Full OAuth lifecycle with automatic 401 handling (parameter added, not yet wired)
- `HTTPClientTransport` accepts an optional `authProvider: (any OAuthClientProvider)?`
- Provider will handle token refresh automatically on 401 responses

### 3. PKCE
- Use CryptoKit directly (no external dependency)
- S256 method only (as required by MCP spec)

### 4. JWT
- Use jwt-kit for all JWT operations
- Support RS256, ES256 for `private_key_jwt`

### 5. Server Auth (if implemented)
- Keep decoupled from specific web framework
- Provide handler functions that can be wired into Hummingbird or other frameworks
- Use hummingbird-auth patterns for middleware

## References

### RFCs
- RFC 6749 - OAuth 2.0 Authorization Framework
- RFC 7636 - PKCE
- RFC 7591 - Dynamic Client Registration
- RFC 7009 - Token Revocation
- RFC 8414 - Authorization Server Metadata
- RFC 8707 - Resource Indicators
- RFC 9728 - Protected Resource Metadata

### Swift Resources
- [jwt-kit documentation](https://docs.vapor.codes/security/jwt/)
- [hummingbird-auth GitHub](https://github.com/hummingbird-project/hummingbird-auth)
- [Swift on Server Authentication (Hummingbird 2)](https://medium.com/@kicsipixel/swift-on-server-authentication-d35884a1e052)
- [Hummingbird JWT example](https://github.com/hummingbird-project/hummingbird-examples/tree/main/auth-jwt)

### MCP SDK References
- TypeScript SDK: `packages/client/src/client/auth.ts`, `packages/server/src/server/auth/`
- Python SDK: `src/mcp/client/auth/`, `src/mcp/server/auth/`

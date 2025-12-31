# Response to claims from @yehorsobko

> I found that they are not 100% aligned with the protocol.

This claim is **invalid** without specific references to code in [my Swift fork](https://github.com/DePasqualeOrg/swift-mcp) and the protocol.

> The client in your fork has become extremely overcomplicated and hard to maintain

This claim is exaggerated, but I'm currently working on a plan to factor out protocol concerns into a Protocol layer like in the TypeScript SDK, which I believe will improve maintainability. I hope to have that ready for review in the coming days.

> [the client] vastly differs from the existing architecture and code style

This claim is **invalid** without specific references. I deliberately avoided sweeping changes that are merely subjective.

Regarding architecture: The only major difference I can see, if it can even be called an architectural difference, is the fact that I broke parts of the long Client and Server files into separate extension files organized by functionality. This is the Swift-idiomatic solution for this situation and improves readability and maintainability.

Regarding code style: I was careful not to make purely stylistic changes and to maintain backward compatibility wherever possible – for example, by adding typealiases with deprecation warnings in the few cases where renaming something made sense.

> Regarding the progress, there’s no way for users to create progress tokens themselves, but it is required according to the protocol.  

This claim is **false**.

The protocol [states](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/8d07c35d3857412a351c595fe01b7bc70664ba06/docs/specification/2025-11-25/basic/utilities/progress.mdx#L19): "Progress tokens can be chosen by the sender using any means, but **MUST** be unique across all active requests."

The **sender** is not the same as the **user**. The sender is the Client or Server (the SDK). There is nothing in the Progress section about **users** being able to create progress tokens themselves. You appear to have misinterpreted the spec and implemented an unnecessary and unergonomic solution to a non-existent problem.

In [my fork](https://github.com/DePasqualeOrg/swift-mcp/blob/489683dd62b629485296bf76bdd0c0ce11ce71cc/Sources/MCP/Client/Client%2BRequests.swift#L233-L236) as well as the [TypeScript](https://github.com/modelcontextprotocol/typescript-sdk/blob/3eb18ec22975b996d57352b5b740004180b9910b/packages/core/src/shared/protocol.ts#L1127) and [Python](https://github.com/modelcontextprotocol/python-sdk/blob/5301298225968ce0fa8ae62870f950709da14dc6/src/mcp/shared/session.py#L259) SDKs, the progress token is automatically set to the request ID.

In your PR [#181](https://github.com/modelcontextprotocol/swift-sdk/pull/181), you require users to manually call [`ProgressToken.unique()`](https://github.com/modelcontextprotocol/swift-sdk/blob/09f1daeb0dc9e67d59d7cec25d4f797373f1a31c/Sources/MCP/Base/Utilities/Progress.swift#L82-L84) and [pass it in `RequestMeta(progressToken: token)`](https://github.com/modelcontextprotocol/swift-sdk/blob/09f1daeb0dc9e67d59d7cec25d4f797373f1a31c/Sources/MCP/Base/Utilities/Progress.swift#L135). This is unergonomic and is not required by the spec.
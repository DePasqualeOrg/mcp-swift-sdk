// Copyright © Anthony DePasquale

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MCPMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ToolMacro.self,
        OutputSchemaMacro.self,
        PromptMacro.self,
    ]
}

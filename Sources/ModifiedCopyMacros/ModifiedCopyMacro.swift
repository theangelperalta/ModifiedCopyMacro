import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

enum ModifiedCopyDiagnostic: DiagnosticMessage {
    case notAStruct
    case propertyTypeProblem(PatternBindingListSyntax.Element)
    
    var severity: DiagnosticSeverity {
        switch self {
        case .notAStruct: .error
        case .propertyTypeProblem: .warning
        }
    }
    
    var message: String {
        switch self {
        case .notAStruct:
            "'@Copyable' can only be applied to a 'struct'"
        case .propertyTypeProblem(let binding):
            "Type error for property '\(binding.pattern)': \(binding)"
        }
    }
    
    var diagnosticID: MessageID {
        switch self {
        case .notAStruct:
            .init(domain: "ModifiedCopyMacros", id: "notAStruct")
        case .propertyTypeProblem(let binding):
            .init(domain: "ModifiedCopyMacros", id: "propertyTypeProblem(\(binding.pattern))")
        }
    }
}

public struct ModifiedCopyMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclSyntax = declaration as? StructDeclSyntax else {
            let diagnostic = Diagnostic(node: Syntax(node), message: ModifiedCopyDiagnostic.notAStruct)
            context.diagnose(diagnostic)
            return []
        }
        
        let structVisibility = structDeclSyntax.modifiers.visibilityText() ?? "internal"
        
        let variables = structDeclSyntax.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
        
        let bindings = variables.flatMap(\.bindings).filter { accessorIsAllowed($0.accessorBlock?.accessors) }
        
        return variables.flatMap { variable in
            let variableVisibility = variable.modifiers.visibilityText() ?? structVisibility
            
            return variable.bindings
                .filter { accessorIsAllowed($0.accessorBlock?.accessors) }
                .compactMap { binding -> DeclSyntax? in
                    let propertyName = binding.pattern
                guard let typeName = binding.typeAnnotation?.type else {
                    let diagnostic = Diagnostic(node: Syntax(node), message: ModifiedCopyDiagnostic.propertyTypeProblem(binding))
                    context.diagnose(diagnostic)
                    return nil
                }
                
                return """
                    /// Returns a copy of the caller whose value for `\(propertyName)` is different.
                    \(raw: variableVisibility) func copy(\(propertyName): \(typeName.trimmed)) -> Self {
                        .init(\(raw: bindings.map { "\($0.pattern): \($0.pattern)" }.joined(separator: ", ")))
                    }
                    """
            }
        }
    }
    
    private static func accessorIsAllowed(_ accessor: AccessorBlockSyntax.Accessors?) -> Bool {
        guard let accessor else { return true }
        return switch accessor {
        case .accessors(let accessorDeclListSyntax):
            !accessorDeclListSyntax.contains {
                $0.accessorSpecifier.text == "get" || $0.accessorSpecifier.text == "set"
            }
        case .getter:
            false
        }
    }
}

extension DeclModifierListSyntax {
    private static let visibilityModifiers: Set = ["private", "fileprivate", "internal", "package", "public", "open"]
    
    func visibilityText() -> String? {
        self.map(\.name.text)
            .first(where: { Self.visibilityModifiers.contains($0) })
    }
}

@main
struct ModifiedCopyPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModifiedCopyMacro.self,
    ]
}

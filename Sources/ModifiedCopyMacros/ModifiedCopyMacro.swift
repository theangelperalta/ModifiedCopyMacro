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
        
        let usableVariables = variables
            .flatMap { $0.bindings }
            .filter { accessorIsAllowed($0.accessorBlock?.accessors) }
            .compactMap { binding -> PatternBindingSyntax? in
                let propertyName = binding.pattern
                guard ((binding.typeAnnotation?.type) != nil) else {
                    let diagnostic = Diagnostic(node: Syntax(node), message: ModifiedCopyDiagnostic.propertyTypeProblem(binding))
                    context.diagnose(diagnostic)
                    return nil
                }
                
                return binding
            }
        
        return [
            """
            /// Returns a copy of the caller allowing you to alter some of its properties while keeping the rest unchanged.
            public func copy(build: (inout Builder) -> Void) -> Self {
                var builder = Builder(original: self)
                build(&builder)
                        
                return builder.to\(structDeclSyntax.name.trimmed)()
            }
            
            public struct Builder {
                \(raw: usableVariables.map { "var \($0.pattern.trimmedDescription.trimmingCharacters(in: .whitespacesAndNewlines)): \($0.typeAnnotation!.type.trimmedDescription.trimmingCharacters(in: .whitespacesAndNewlines))"}.joined(separator: "\n    "))
                    
                fileprivate init(original: \(structDeclSyntax.name.trimmed)) {
                    \(raw: usableVariables.map { "self.\($0.pattern.trimmedDescription.trimmingCharacters(in: .whitespaces)) = original.\($0.pattern.trimmedDescription.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n"))
                }
                
                fileprivate func to\(structDeclSyntax.name.trimmed)() -> \(structDeclSyntax.name.trimmed) {
                    return \(structDeclSyntax.name.trimmed)(\(raw: usableVariables.map { "\($0.pattern.trimmed): \($0.pattern.trimmed)" }.joined(separator: ", ")))
                }
            }
            """
        ]
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

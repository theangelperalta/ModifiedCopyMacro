import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
import ModifiedCopyMacros
import ModifiedCopy

let testMacros: [String: Macro.Type] = [
    "Copyable": ModifiedCopyMacro.self,
]

@Copyable
struct Person: Equatable {
    var name: String
    
    let age: Int
    
    /// This should not generate a copy function because it's not a stored property.
    var fullName: String {
        get {
            name
        }
        set {
            name = newValue
        }
    }
    
    /// This should not generate a copy function because it's not a stored property.
    var uppercasedName: String {
        name.uppercased()
    }
    
    var nickName: String? = "Bobby Tables" {
        didSet {
            print("nickName changed to \(nickName ?? "(nil)")")
        }
    }
}

final class ModifiedCopyTests: XCTestCase {
    func testMacroExpansion() {
        
        
        assertMacroExpansion(
            #"""
            @Copyable
            public struct Person {
                private(set) var name: String
                
                let age: Int
                
                private var favoriteColor: String
                
                /// This should not generate a copy function because it's not a stored property.
                var fullName: String {
                    get {
                        name
                    }
                    set {
                        name = newValue
                    }
                }
                
                /// This should not generate a copy function because it's not a stored property.
                var uppercasedName: String {
                    name.uppercased()
                }
                
                var nickName: String? = "Bobby Tables" {
                    didSet {
                        print("nickName changed to \(nickName ?? "(nil)")")
                    }
                }
                
                init(name: String, age: Int, favoriteColor: String, nickName: String? = nil) {
                    self.name = name
                    self.age = age
                    self.favoriteColor = favoriteColor
                    self.nickName = nickName
                }
            }
            """#,
            expandedSource:
            #"""
            public struct Person {
                private(set) var name: String
                
                let age: Int
                
                private var favoriteColor: String
                
                /// This should not generate a copy function because it's not a stored property.
                var fullName: String {
                    get {
                        name
                    }
                    set {
                        name = newValue
                    }
                }
                
                /// This should not generate a copy function because it's not a stored property.
                var uppercasedName: String {
                    name.uppercased()
                }
                
                var nickName: String? = "Bobby Tables" {
                    didSet {
                        print("nickName changed to \(nickName ?? "(nil)")")
                    }
                }
                
                init(name: String, age: Int, favoriteColor: String, nickName: String? = nil) {
                    self.name = name
                    self.age = age
                    self.favoriteColor = favoriteColor
                    self.nickName = nickName
                }

                /// Returns a copy of the caller allowing you to alter some of its properties while keeping the rest unchanged.
                public func copy(build: (inout Builder) -> Void) -> Self {
                    var builder = Builder(original: self)
                    build(&builder)
            
                    return builder.toPerson()
                }

                public struct Builder {
                    var name: String
                    var age: Int
                    var favoriteColor: String
                    var nickName: String?
                    
                    fileprivate init(original: Person) {
                        self.name = original.name
                        self.age = original.age
                        self.favoriteColor = original.favoriteColor
                        self.nickName = original.nickName
                    }
                    
                    fileprivate func toPerson() -> Person {
                        return Person(name: name, age: age, favoriteColor: favoriteColor, nickName: nickName)
                    }
                }
            }
            """#,
            macros: testMacros
        )
    }
    
    func testNewLetValue() {
        let person = Person(name: "Walter White", age: 50, nickName: "Heisenberg")
        let copiedPerson = person.copy { $0.age = 51 }
        XCTAssertEqual(Person(name: "Walter White", age: 51, nickName: "Heisenberg"), copiedPerson)
    }
    
    func testNewVarValue() {
        let person = Person(name: "Walter White", age: 50, nickName: "Heisenberg")
        let copiedPerson = person.copy { $0.name = "W.W." }
        XCTAssertEqual(Person(name: "W.W.", age: 50, nickName: "Heisenberg"), copiedPerson)
    }
    
    func testNewOptionalValue() {
        let person = Person(name: "Walter White", age: 50, nickName: "Heisenberg")
        let copiedPerson = person.copy { $0.nickName =  nil}
        XCTAssertEqual(Person(name: "Walter White", age: 50, nickName: nil), copiedPerson)
    }
    
    func testChainedNewValues() {
        let person = Person(name: "Walter White", age: 50, nickName: "Heisenberg")
        let copiedPerson = person.copy { $0.name = "Skyler White"; $0.age = 48 }
        XCTAssertEqual(Person(name: "Skyler White", age: 48, nickName: "Heisenberg"), copiedPerson)
    }
}

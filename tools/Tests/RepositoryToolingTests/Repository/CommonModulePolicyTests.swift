import Testing

@testable import RepositoryTooling

@Suite("Common module boundary")
struct CommonModulePolicyTests {
    private let modelPath = "Sources/LittleSwitchCommon/Domain/Providers/Provider.swift"

    @Test("Common rejects implementation imports even inside conditional compilation")
    func implementationImports() {
        let source = """
            import Foundation
            #if os(macOS)
            import SwiftUI
            #endif
            import struct LittleSwitchCore.Provider
            import LittleSwitchWire
            """
        #expect(
            CommonModulePolicy.violations(files: [modelPath: source]) == [
                "\(modelPath): LittleSwitchCommon must not import LittleSwitchCore",
                "\(modelPath): LittleSwitchCommon must not import LittleSwitchWire",
                "\(modelPath): LittleSwitchCommon must not import SwiftUI",
            ])
    }

    @Test("Foundation imports and import-like comments or strings are allowed")
    func valueImports() {
        let source = """
            import Foundation
            import struct Foundation.Date
            // import LittleSwitchCore
            let description = "import SwiftUI"
            """
        #expect(CommonModulePolicy.violations(files: [modelPath: source]).isEmpty)
        #expect(
            CommonModulePolicy.violations(files: [
                "Sources/LittleSwitchUI/Settings/Root/SettingsView.swift": "import SwiftUI"
            ]).isEmpty)
    }

    @Test("Common stays dependency-free and its consumers declare the module explicitly")
    func targetDependencies() {
        let manifest = """
            let targets = [
                .target(name: "LittleSwitchCommon"),
                .target(name: "LittleSwitchCore", dependencies: ["LittleSwitchCommon", "LittleSwitchWire"]),
                .target(name: "LittleSwitchSearch", dependencies: ["LittleSwitchCommon", "LittleSwitchTransport"]),
                .target(name: "LittleSwitchUI", dependencies: ["LittleSwitchCommon", "LittleSwitchCore"]),
            ]
            """
        #expect(CommonModulePolicy.violations(files: ["Package.swift": manifest]).isEmpty)
        #expect(
            CommonModulePolicy.violations(files: [
                "Package.swift": ".target(name: \"LittleSwitchCommon\", dependencies: [])"
            ]).isEmpty)
    }

    @Test("SDK or implementation dependencies cannot be added to Common")
    func commonDependencies() {
        for dependencies in [
            "[\"LittleSwitchCore\"]",
            "[.product(name: \"OrderedJSON\", package: \"orderedjson\")]",
            "sharedDependencies",
        ] {
            let manifest = ".target(name: \"LittleSwitchCommon\", dependencies: \(dependencies))"
            #expect(
                CommonModulePolicy.violations(files: ["Package.swift": manifest]) == [
                    "Package.swift: LittleSwitchCommon must have no target dependencies"
                ])
        }
    }

    @Test("Core, Search and UI must not rely on transitive Common visibility")
    func missingDirectDependencies() {
        let manifest = """
            .target(name: "LittleSwitchCommon")
            .target(name: "LittleSwitchCore", dependencies: ["LittleSwitchWire"])
            .target(name: "LittleSwitchSearch")
            .target(name: "LittleSwitchUI", dependencies: sharedDependencies)
            """
        #expect(
            CommonModulePolicy.violations(files: ["Package.swift": manifest]) == [
                "Package.swift: LittleSwitchCore must directly depend on LittleSwitchCommon",
                "Package.swift: LittleSwitchSearch must directly depend on LittleSwitchCommon",
                "Package.swift: LittleSwitchUI must directly depend on LittleSwitchCommon",
            ])
    }

    @Test("A Common source tree needs its production target, not a test target or a comment")
    func missingTarget() {
        let manifest = """
            // .target(name: "LittleSwitchCommon")
            .testTarget(name: "LittleSwitchCommon")
            .target(name: "AnotherTarget")
            """
        #expect(
            CommonModulePolicy.violations(files: ["Package.swift": manifest, modelPath: "struct Provider {}"])
                == ["Package.swift: missing LittleSwitchCommon target"])
        #expect(CommonModulePolicy.violations(files: [:]).isEmpty)
        #expect(CommonModulePolicy.violations(files: ["Package.swift": manifest]).isEmpty)
    }

    @Test("Computed target names and product dependencies do not establish a local module boundary")
    func indirectDeclarations() {
        for name in ["targetName", #""LittleSwitch\(suffix)""#] {
            #expect(
                CommonModulePolicy.violations(files: [
                    "Package.swift": ".target(name: \(name))", modelPath: "struct Provider {}",
                ]) == ["Package.swift: missing LittleSwitchCommon target"])
        }
        #expect(
            CommonModulePolicy.violations(files: [
                "Package.swift": """
                .target(name: "LittleSwitchCommon")
                .target(name: "LittleSwitchCore", dependencies: [
                    .product(name: "LittleSwitchCommon", package: "other-package")
                ])
                """
            ]) == ["Package.swift: LittleSwitchCore must directly depend on LittleSwitchCommon"])
    }
}

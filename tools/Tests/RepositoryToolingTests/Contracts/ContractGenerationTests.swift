import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Contract generation ownership", .serialized)
struct ContractGenerationTests {
    @Test func qualificationFilesAreOwnedAndCheckNeverRepairsThem() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let files = try ContractGenerationFileSystem.generate(root: root)
            let path = try #require(
                files.first { $0.hasPrefix("Tests/LittleSwitchWireTests/Generated/Qualification/TestFixture/") })
            let manifest = try JSONDecoder().decode(
                ContractGenerationManifest.self,
                from: Data(contentsOf: root.appendingPathComponent(ContractGenerationPaths.manifest)))
            #expect(manifest.files.contains { $0.path == path })
            let drifted = Data("// qualification drift\n".utf8)
            try drifted.write(to: root.appendingPathComponent(path))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.check(root: root) }
            #expect(try Data(contentsOf: root.appendingPathComponent(path)) == drifted)
        }
    }

    @Test func generatesDeterministicallyAndCheckDoesNotRepair() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let first = try ContractGenerationFileSystem.generate(root: root)
            let manifest = try Data(contentsOf: root.appendingPathComponent(ContractGenerationPaths.manifest))
            #expect(try ContractGenerationFileSystem.generate(root: root) == first)
            #expect(try Data(contentsOf: root.appendingPathComponent(ContractGenerationPaths.manifest)) == manifest)
            #expect(try ContractGenerationFileSystem.check(root: root) == first)
            let path = try #require(first.first)
            let changed = Data("// manually changed\n".utf8)
            try changed.write(to: root.appendingPathComponent(path))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.check(root: root) }
            #expect(try Data(contentsOf: root.appendingPathComponent(path)) == changed)
            #expect(try Data(contentsOf: root.appendingPathComponent(ContractGenerationPaths.manifest)) == manifest)
        }
    }

    @Test func detectsManifestByteDriftWithoutMutation() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            _ = try ContractGenerationFileSystem.generate(root: root)
            let url = root.appendingPathComponent(ContractGenerationPaths.manifest)
            let drifted = try Data(contentsOf: url) + Data([10])
            try drifted.write(to: url)
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.check(root: root) }
            #expect(try Data(contentsOf: url) == drifted)
        }
    }

    @Test func removesOnlyPreviouslyOwnedOutputs() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let old = try #require(ContractGenerationFileSystem.generate(root: root).first)
            let unrelated = root.appendingPathComponent("Tests/LittleSwitchWireTests/Generated/keep.txt")
            try Data("keep".utf8).write(to: unrelated)
            try projections(name: "NewFixture").write(to: root.appendingPathComponent("schemas/projections.json"))
            let new = try ContractGenerationFileSystem.generate(root: root)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(old).path))
            #expect(new.contains("Tests/LittleSwitchWireTests/Generated/Fixtures/NewFixture.swift"))
            #expect(new.count == 5)
            #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        }
    }

    @Test func rejectsCollisionAndInvalidSchemaBeforeInstallingAnything() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            try projections(duplicate: true).write(to: root.appendingPathComponent("schemas/projections.json"))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(ContractGenerationPaths.manifest).path))
            try projections().write(to: root.appendingPathComponent("schemas/projections.json"))
            try Data(#"{"type":"string","pattern":"bad"}"#.utf8).write(
                to: root.appendingPathComponent("schemas/fixtures/test.json"))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Tests").path))
        }
    }

    @Test func rejectsUnsafeOwnedPathsAndSymlinks() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            for path in [
                "/tmp/wire.swift", "Tests/LittleSwitchWireTests/Generated/../secret.swift", "Sources/Other.swift",
            ] {
                let manifest = ContractGenerationManifest(
                    formatVersion: 1, generator: "fixture", inputs: [], files: [.init(path: path, sha256: "")])
                try manifest.data().write(to: root.appendingPathComponent(ContractGenerationPaths.manifest))
                #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            }
            try FileManager.default.removeItem(at: root.appendingPathComponent(ContractGenerationPaths.manifest))
            let parent = root.appendingPathComponent("Tests/LittleSwitchWireTests")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: parent.appendingPathComponent("Generated"), withDestinationURL: root)
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
        }
    }

    @Test func protectsUnownedExistingFiles() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let file = root.appendingPathComponent("Tests/LittleSwitchWireTests/Generated/Fixtures/TestFixture.swift")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("user file".utf8).write(to: file)
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(try String(contentsOf: file, encoding: .utf8) == "user file")
        }
    }

    @Test func cliGeneratesChecksAndReportsDrift() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let generated = try ToolingCLI.run(["--root", root.path, "contracts", "generate"], currentDirectory: root)
            #expect(generated.status == 0)
            #expect(generated.stdout == "Generated 5 Swift files.\n")
            #expect(try ToolingCLI.run(["contracts", "check"], currentDirectory: root).status == 0)
            try Data().write(
                to: root.appendingPathComponent("Tests/LittleSwitchWireTests/Generated/Fixtures/TestFixture.swift"))
            let checked = try ToolingCLI.run(["contracts", "check"], currentDirectory: root)
            #expect(checked.status != 0)
            #expect(checked.stderr.contains("differs"))
        }
    }

    @Test func compatibilityCannotWeakenAUnionTaggedByBranchSelection() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            try selectedUnionFixture.write(to: root.appendingPathComponent("schemas/fixtures/test.json"))
            let projection =
                #"""
                {
                  "formatVersion": 1,
                  "contracts": [
                    {
                      "root": "Fixture",
                      "schema": "schemas/fixtures/test.json",
                      "swiftName": "TestFixture",
                      "branches": [
                        0,
                        1
                      ],
                      "output": "Tests/LittleSwitchWireTests/Generated",
                      "importModule": "LittleSwitchWire"
                    }
                  ]
                }
                """#
            try Data(projection.utf8).write(to: root.appendingPathComponent("schemas/projections.json"))
            for pointer in ["#/definitions/FirstTag", "#/definitions/First/properties/type"] {
                let rule = """
                    {"formatVersion":1,"overrides":[{"id":"weaken","root":"Fixture","projection":"TestFixture",
                    "pointer":"\(pointer)","operation":"openEnum","reason":"Qualification fixture",
                    "source":"Local schema","fixtures":["schemas/fixtures/test.json"]}]}
                    """
                try Data(rule.utf8).write(to: root.appendingPathComponent("schemas/compatibility.json"))
                #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
                #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Tests").path))
            }
        }
    }

    @Test func opaqueProjectionCannotEraseSelectedTaggedDispatch() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            try selectedUnionFixture.write(to: root.appendingPathComponent("schemas/fixtures/test.json"))
            for pointer in ["#/definitions/First", "#/definitions/FirstTag", "#/definitions/First/properties/type"] {
                let projection = """
                    {"formatVersion":1,"contracts":[{"root":"Fixture","schema":"schemas/fixtures/test.json",
                    "swiftName":"TestFixture","branches":[0,1],"opaque":["\(pointer)"],
                    "output":"Tests/LittleSwitchWireTests/Generated","importModule":"LittleSwitchWire"}]}
                    """
                try Data(projection.utf8).write(to: root.appendingPathComponent("schemas/projections.json"))
                #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
                #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Tests").path))
            }
        }
    }

    @Test func aliasedParentCannotMakeDiscriminatorOptionalBeforeOpaqueProjection() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            try selectedUnionFixture.write(to: root.appendingPathComponent("schemas/fixtures/test.json"))
            let projection = """
                {"formatVersion":1,"contracts":[{"root":"Fixture","schema":"schemas/fixtures/test.json",
                "swiftName":"TestFixture","branches":[0,1],"opaque":["#/definitions/First/properties/type"],
                "output":"Tests/LittleSwitchWireTests/Generated","importModule":"LittleSwitchWire"}]}
                """
            try Data(projection.utf8).write(to: root.appendingPathComponent("schemas/projections.json"))
            let rule = """
                {"formatVersion":1,"overrides":[{"id":"weaken","root":"Fixture","projection":"TestFixture",
                "pointer":"#/anyOf/0/properties/type","operation":"optional","reason":"Qualification fixture",
                "source":"Local schema","fixtures":["schemas/fixtures/test.json"]}]}
                """
            try Data(rule.utf8).write(to: root.appendingPathComponent("schemas/compatibility.json"))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Tests").path))
        }
    }

    private var selectedUnionFixture: Data {
        Data(
            ##"""
            {
              "anyOf": [
                {
                  "$ref": "#/definitions/First"
                },
                {
                  "$ref": "#/definitions/Second"
                },
                {
                  "type": "string"
                }
              ],
              "definitions": {
                "FirstTag": {
                  "const": "first"
                },
                "First": {
                  "type": "object",
                  "properties": {
                    "type": {
                      "$ref": "#/definitions/FirstTag"
                    },
                    "text": {
                      "type": "string"
                    }
                  },
                  "required": [
                    "type",
                    "text"
                  ]
                },
                "Second": {
                  "type": "object",
                  "properties": {
                    "type": {
                      "const": "second"
                    },
                    "count": {
                      "type": "number"
                    }
                  },
                  "required": [
                    "type",
                    "count"
                  ]
                }
              }
            }
            """##
            .utf8)
    }

}

extension ContractGenerationTests {
    @Test func pinnedSDKInputsAreHashedAndAttributed() throws {
        try withTemporaryDirectory { root in
            try prepareSDK(root)
            let files = try ContractGenerationFileSystem.generate(root: root)
            #expect(files.contains("Sources/LittleSwitchWire/Generated/OpenAI/OpenAITestRecord.swift"))
            #expect(files.count == 5)
            let source = try String(contentsOf: root.appendingPathComponent(files[0]), encoding: .utf8)
            #expect(source.contains("// SDK: fixture-sdk 1.0.0\n"))
            #expect(source.contains("// Schema SHA256: "))
            #expect(try ContractGenerationFileSystem.check(root: root) == files)
        }
    }

    @Test(arguments: ["unknown-root", "hash", "provenance", "output", "compatibility"])
    func invalidSDKInputsDoNotPublishPartialOutputs(problem: String) throws {
        try withTemporaryDirectory { root in
            try prepareSDK(root)
            let path: String
            let value: String
            switch problem {
            case "unknown-root":
                path = "schemas/roots.json"
                value = #"{"roots":[]}"#
            case "hash":
                path = "schemas/upstream/Test.schema.json"
                value = #"{"type":"string","enum":["changed"]}"#
            case "provenance":
                path = "schemas/upstream/manifest.json"
                let original = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
                value = original.replacingOccurrences(of: #""id":"test-sdk""#, with: #""id":"another-sdk""#)
            case "output":
                path = "schemas/projections.json"
                value =
                    #"{"formatVersion":1,"contracts":[{"root":"Fixture","swiftName":"OpenAITestRecord","output":"Sources/Unowned"}]}"#
            default:
                path = "schemas/compatibility.json"
                value =
                    ##"""
                    {"formatVersion":1,"overrides":[{"id":"unselected","root":"Fixture","projection":"Other",
                    "pointer":"#","operation":"openEnum","reason":"Fixture","source":"Fixture",
                    "fixtures":["schemas/upstream/Test.schema.json"]}]}
                    """##
            }
            try Data(value.utf8).write(to: root.appendingPathComponent(path))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path))
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(ContractGenerationPaths.manifest).path))
        }
    }

    @Test(arguments: ["version", "duplicate"])
    func malformedOwnershipManifestKeepsExistingFiles(problem: String) throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let files = try ContractGenerationFileSystem.generate(root: root)
            let path = try #require(files.first)
            let original = try Data(contentsOf: root.appendingPathComponent(path))
            let file = ContractGenerationManifest.File(path: path, sha256: ContractGenerationManifest.hash(original))
            let malformed = ContractGenerationManifest(
                formatVersion: problem == "version" ? 2 : 1,
                generator: "fixture",
                inputs: [],
                files: problem == "duplicate" ? [file, file] : [file])
            let bytes = try malformed.data()
            try bytes.write(to: root.appendingPathComponent(ContractGenerationPaths.manifest))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(try Data(contentsOf: root.appendingPathComponent(path)) == original)
            #expect(try Data(contentsOf: root.appendingPathComponent(ContractGenerationPaths.manifest)) == bytes)
        }
    }

    @Test func localFixtureSchemasCannotEnterTheProductionModule() throws {
        try withTemporaryDirectory { root in
            try prepare(root)
            let source = try #require(String(data: projections(), encoding: .utf8))
            let invalid = source.replacingOccurrences(
                of: "Tests/LittleSwitchWireTests/Generated", with: "Sources/LittleSwitchWire/Generated")
            try Data(invalid.utf8).write(to: root.appendingPathComponent("schemas/projections.json"))
            #expect(throws: ContractGenerationError.self) { try ContractGenerationFileSystem.generate(root: root) }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path))
        }
    }

    private func prepareSDK(_ root: URL) throws {
        try prepare(root)
        let schema = Data(#"{"type":"string","enum":["a","b"]}"#.utf8)
        try schema.write(to: root.appendingPathComponent("schemas/upstream/Test.schema.json"))
        let files = [
            "schemas/roots.json": #"{"roots":[{"name":"Fixture","schema":"Test.schema.json","sdk":"test-sdk"}]}"#,
            "schemas/upstream/manifest.json": """
            {"artifacts":[{"path":"Test.schema.json","sha256":"\(ContractGenerationManifest.hash(schema))"}],
             "sources":[{"id":"test-sdk","package":"fixture-sdk","version":"1.0.0"}]}
            """,
            "schemas/projections.json":
                #"{"formatVersion":1,"contracts":[{"root":"Fixture","swiftName":"OpenAITestRecord"}]}"#,
        ]
        for (path, content) in files { try Data(content.utf8).write(to: root.appendingPathComponent(path)) }
    }

    private func prepare(_ root: URL) throws {
        for directory in ["schemas/fixtures", "schemas/upstream"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        try Data(#"{"roots":[]}"#.utf8).write(to: root.appendingPathComponent("schemas/roots.json"))
        try Data(#"{"artifacts":[]}"#.utf8).write(to: root.appendingPathComponent("schemas/upstream/manifest.json"))
        try Data(#"{"formatVersion":1,"overrides":[]}"#.utf8).write(
            to: root.appendingPathComponent("schemas/compatibility.json"))
        try Data(#"{"type":"string","enum":["a","b"]}"#.utf8).write(
            to: root.appendingPathComponent("schemas/fixtures/test.json"))
        try projections().write(to: root.appendingPathComponent("schemas/projections.json"))
    }

    private func projections(name: String = "TestFixture", duplicate: Bool = false) -> Data {
        let rule = """
            {"root":"Fixture","schema":"schemas/fixtures/test.json","swiftName":"\(name)","output":"Tests/LittleSwitchWireTests/Generated","importModule":"LittleSwitchWire"}
            """
        return Data("{\"formatVersion\":1,\"contracts\":[\(rule)\(duplicate ? "," + rule : "")]}".utf8)
    }
}

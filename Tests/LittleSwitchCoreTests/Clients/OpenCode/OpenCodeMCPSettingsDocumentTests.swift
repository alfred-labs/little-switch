import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("OpenCode MCP settings document")
struct OpenCodeMCPSettingsDocumentTests {
    @Test("Legacy managed settings decode without MCP ownership")
    func legacyDecoding() throws {
        let legacy = openCodeManagedSettings()
        let decoded = try JSONDecoder().decode(
            OpenCodeManagedSettings.self,
            from: JSONEncoder().encode(legacy)
        )

        #expect(decoded.mcp == nil)
        #expect(decoded == legacy)
        #expect(
            try JSONDecoder().decode(
                OpenCodeManagedSettings.self,
                from: JSONEncoder().encode(managed)
            ) == managed
        )
    }

    @Test("Activation and restore preserve other MCP servers and independent external edits")
    func independentOwnership() throws {
        let original = Data(
            #"{"model":"old/model","mcp":{"web":false,"keep":{"type":"local","command":["keep"]}},"permission":"ask"}"#
                .utf8
        )
        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)
        var current = try jsonObject(activated)
        var servers = try #require(current["mcp"] as? [String: Any])
        #expect(servers["keep"] as? NSDictionary == ["type": "local", "command": ["keep"]] as NSDictionary)
        servers["external"] = ["type": "remote", "url": "https://external.example/mcp"]
        current["mcp"] = servers
        current["permission"] = "deny"

        let restored = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: encode(current),
                original: original,
                managed: managed
            )
        )
        let expected = Data(
            #"{"model":"old/model","mcp":{"web":false,"keep":{"type":"local","command":["keep"]},"external":{"type":"remote","url":"https://external.example/mcp"}},"permission":"deny"}"#
                .utf8
        )
        #expect(try jsonObject(restored) as NSDictionary == jsonObject(expected) as NSDictionary)
    }

    @Test("MCP restoration preserves exact externally changed or removed owned values")
    func driftRestore() throws {
        let original = Data(#"{"mcp":{"web":{"type":"local","command":["old"]}}}"#.utf8)
        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)
        var changed = try jsonObject(activated)
        changed["mcp"] = ["web": ["enabled": false], "other": false]

        let restored = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: encode(changed), original: original, managed: managed
            )
        )
        #expect(
            try jsonObject(restored) as NSDictionary
                == ["mcp": ["web": ["enabled": false], "other": false]] as NSDictionary
        )

        changed.removeValue(forKey: "mcp")
        let deleted = try #require(
            try OpenCodeSettingsDocument.restoring(
                current: encode(changed), original: original, managed: managed
            )
        )
        #expect(try jsonObject(deleted).isEmpty)
    }

    @Test("Restore distinguishes absent and empty original MCP containers")
    func containerExistence() throws {
        let created = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        #expect(
            try OpenCodeSettingsDocument.restoring(current: created, original: nil, managed: managed) == nil
        )

        let original = Data(#"{"mcp":{}}"#.utf8)
        let activated = try OpenCodeSettingsDocument.activating(original, managed: managed)
        let restored = try #require(
            try OpenCodeSettingsDocument.restoring(current: activated, original: original, managed: managed)
        )
        #expect(try jsonObject(restored) as NSDictionary == ["mcp": [:]] as NSDictionary)

        var extended = try jsonObject(created)
        extended["mcp"] = ["web": try serverObject(), "external": false]
        let extendedRestore = try #require(
            try OpenCodeSettingsDocument.restoring(current: encode(extended), original: nil, managed: managed)
        )
        #expect(try jsonObject(extendedRestore) as NSDictionary == ["mcp": ["external": false]] as NSDictionary)
    }

    @Test("MCP drift requires complete equality of the owned entry")
    func exactManagedDetection() throws {
        let activated = try OpenCodeSettingsDocument.activating(nil, managed: managed)
        #expect(try OpenCodeSettingsDocument.isManaged(activated, managed: managed))
        var root = try jsonObject(activated)
        root["mcp"] = ["web": try serverObject(), "unrelated": false]
        #expect(try OpenCodeSettingsDocument.isManaged(encode(root), managed: managed))

        var changedServer = try serverObject()
        changedServer["extra"] = true
        root["mcp"] = ["web": changedServer]
        #expect(!(try OpenCodeSettingsDocument.isManaged(encode(root), managed: managed)))

        root["mcp"] = [:] as [String: Any]
        #expect(!(try OpenCodeSettingsDocument.isManaged(encode(root), managed: managed)))
        root.removeValue(forKey: "mcp")
        #expect(!(try OpenCodeSettingsDocument.isManaged(encode(root), managed: managed)))
    }

    @Test("Invalid MCP containers fail explicitly", arguments: ["null", "false", "42", "[]", #""invalid""#])
    func invalidMCPContainer(value: String) throws {
        let invalid = Data("{\"mcp\":\(value)}".utf8)
        #expect(throws: OpenCodeSettingsDocument.Error.nonObjectMCP) {
            try OpenCodeSettingsDocument.activating(invalid, managed: managed)
        }
        let legacyActivation = try OpenCodeSettingsDocument.activating(invalid, managed: openCodeManagedSettings())
        #expect(throws: OpenCodeSettingsDocument.Error.nonObjectMCP) {
            try OpenCodeSettingsDocument.isManaged(legacyActivation, managed: managed)
        }
        #expect(throws: OpenCodeSettingsDocument.Error.nonObjectMCP) {
            try OpenCodeSettingsDocument.restoring(current: legacyActivation, original: nil, managed: managed)
        }
    }

    @Test("Legacy restore and drift checks never inspect or claim MCP entries")
    func legacyOwnership() throws {
        let legacy = openCodeManagedSettings()
        for original in [Data(#"{"mcp":false}"#.utf8), Data(#"{"mcp":{"little-switch":null}}"#.utf8)] {
            let activated = try OpenCodeSettingsDocument.activating(original, managed: legacy)
            #expect(try OpenCodeSettingsDocument.isManaged(activated, managed: legacy))
            let restored = try #require(
                try OpenCodeSettingsDocument.restoring(current: activated, original: original, managed: legacy)
            )
            #expect(try jsonObject(restored) as NSDictionary == jsonObject(original) as NSDictionary)
        }
    }

    private var managed: OpenCodeManagedSettings {
        var managed = openCodeManagedSettings()
        managed.mcp = .littleSwitch
        return managed
    }

    private func serverObject() throws -> [String: Any] {
        var object = try jsonObject(JSONEncoder().encode(OpenCodeManagedMCPServer.littleSwitch))
        object.removeValue(forKey: "name")
        return object
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

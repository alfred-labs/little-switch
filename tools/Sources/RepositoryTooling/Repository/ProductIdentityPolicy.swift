import Foundation

enum ProductIdentityPolicy {
    static let allowedLegacyPaths: Set<String> = [
        "Sources/LittleSwitchCore/Configuration/Product/ProductIdentity.swift",
        "Sources/LittleSwitchCore/Clients/Claude/ClaudeProfile.swift",
        "Sources/LittleSwitchUI/Application/Coordination/ApplicationCoordinatorLive.swift",
        "Tests/LittleSwitchCoreTests/Clients/Claude/ClaudeProfileTests.swift",
        "Tests/LittleSwitchCoreTests/Configuration/Product/ProductIdentityTests.swift",
    ]

    static var rules: [RepositoryTextRule] {
        [
            RepositoryTextRule(
                "Package.swift",
                required: [
                    #"name: "LittleSwitch""#, #"name: "LittleSwitchCore""#, #"name: "LittleSwitchUI""#,
                ]),
            RepositoryTextRule("tools/build-app.sh", required: [#"LittleSwitch\.app"#, "release/LittleSwitch"]),
            RepositoryTextRule(
                "tools/ci/verify-bundle.sh", required: [#"LittleSwitch\.app"#, #"com\.alfredlabs\.littleswitch"#]),
        ]
    }

    static func legacyViolations(files: [String: String], rootPath: String) -> [String] {
        let forbidden = [
            ["Model", "Switch", "er"].joined(), ["LittleSwitch", "er"].joined(),
            ["little_switch", "er"].joined(), ["littleswitch", "er"].joined(), ["little-switch", "er"].joined(),
        ]
        return files.sorted { $0.key < $1.key }.filter { !allowedLegacyPaths.contains($0.key) }.flatMap { path, text in
            let contents = text.replacingOccurrences(of: rootPath, with: "<repository>")
            return forbidden.filter(contents.contains).map { "\(path) contains legacy product spelling \($0)" }
        }
    }

    static func bundleViolations(_ contents: String?) -> [String] {
        guard let contents,
            let properties = try? PropertyListSerialization.propertyList(from: Data(contents.utf8), format: nil)
                as? [String: Any]
        else { return ["packaging/Info.plist must be a valid property-list dictionary"] }
        let expected = [
            "CFBundleName": "LittleSwitch", "CFBundleExecutable": "LittleSwitch",
            "CFBundleIdentifier": "com.alfredlabs.littleswitch", "CFBundleIconFile": "AppIcon.icns",
        ]
        return expected.sorted { $0.key < $1.key }.compactMap { key, value in
            guard properties[key] as? String == value else {
                return "packaging/Info.plist: \(key) must equal \(value)"
            }
            return nil
        }
    }
}

import Foundation

enum AppIconPolicy {
    static var rules: [RepositoryTextRule] {
        [
            RepositoryTextRule(
                "packaging/AppIcon.svg",
                required: ["#FFFFFF", "#D8D9DC", "#191A1D", "#5D5F65", "#F6F6F4"],
                forbidden: ["(?i)connector|bridge|vendor|Nintendo"]),
            RepositoryTextRule(
                "tools/generate-app-icon.sh",
                required: [#"cp "\$master_icon" "\$iconset/icon_512x512@2x\.png""#],
                forbidden: [#"render icon_512x512@2x\.png 1024"#]),
            RepositoryTextRule(
                "tools/build-app.sh", required: [#"generate-app-icon\.sh"#, #"Contents/Resources/AppIcon\.icns"#]),
            RepositoryTextRule(
                "tools/ci/verify-bundle.sh",
                required: [
                    "CFBundleIconFile", #"verify-app-icon\.sh"#, #"Contents/Resources/AppIcon\.icns"#,
                ]),
        ]
    }

    static func sourceViolations(_ source: String?) -> [String] {
        guard let source,
            let document = try? XMLDocument(xmlString: source, options: .nodeLoadExternalEntitiesNever),
            let root = document.rootElement(), root.name == "svg"
        else { return ["packaging/AppIcon.svg must be valid SVG XML"] }
        var issues: [String] = []
        if root.attribute(forName: "viewBox")?.stringValue != "0 0 1024 1024" {
            issues.append("packaging/AppIcon.svg must have a 1024-pixel square viewBox")
        }
        let identifiers = identifiers(in: root)
        let required = [
            "background", "left-module", "right-module", "left-indicator", "right-indicator", "up-arrow", "down-arrow",
        ]
        for identifier in required where identifiers.filter({ $0 == identifier }).count != 1 {
            issues.append("packaging/AppIcon.svg must contain exactly one \(identifier) element")
        }
        return issues
    }

    private static func identifiers(in element: XMLElement) -> [String] {
        let own = element.attribute(forName: "id")?.stringValue.map { [$0] } ?? []
        let children = element.children?.compactMap { $0 as? XMLElement } ?? []
        return own + children.flatMap { identifiers(in: $0) }
    }
}

enum RepositoryPolicies {
    static func violations(files: [String: String], paths: Set<String>, rootPath: String) -> [String] {
        let rules =
            CoverageBoundaryPolicy.rules + BrandAssetPolicy.rules + ProductIdentityPolicy.rules + AppIconPolicy.rules
        var issues = rules.flatMap { $0.violations(in: files) }
        issues += CommonModulePolicy.violations(files: files)
        issues += ProductIdentityPolicy.legacyViolations(files: files, rootPath: rootPath)
        issues += ProductIdentityPolicy.bundleViolations(files["packaging/Info.plist"])
        issues += AppIconPolicy.sourceViolations(files["packaging/AppIcon.svg"])
        if paths.contains("packaging/licenses") {
            issues.append("packaging/licenses must be absent; bundle the consolidated THIRD_PARTY_NOTICES.md")
        }
        return issues.sorted()
    }
}

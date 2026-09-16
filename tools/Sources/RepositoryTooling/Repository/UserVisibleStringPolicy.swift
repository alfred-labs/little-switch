enum UserVisibleStringPolicy {
    static func violations(files: [String: String]) -> [String] {
        files.sorted { $0.key < $1.key }
            .filter { $0.key.hasPrefix("Sources/LittleSwitchUI/") && $0.key.hasSuffix(".swift") }
            .flatMap { path, source in
                UserVisibleStringScanner.scan(source: source, filePath: path).map(\.description)
            }
    }
}

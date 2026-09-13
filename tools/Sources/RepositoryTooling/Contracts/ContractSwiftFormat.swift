import Foundation

enum ContractSwiftFormat {
    static func format(_ source: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LittleSwitch-contract-format-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Generated.swift")
        let config = directory.appendingPathComponent(".swift-format")
        try Data(source.utf8).write(to: file)
        try Data(#"{"indentation":{"spaces":4},"lineLength":120,"respectsExistingLineBreaks":true,"version":1}"#.utf8)
            .write(to: config)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swift", "format", "format", "--configuration", config.path, file.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let formatted = String(data: data, encoding: .utf8) else {
            throw ContractGenerationError(contract: "swift-format", reason: "Unable to format generated Swift")
        }
        return formatted
    }
}

import Foundation

func withTemporaryDirectory<Value>(_ body: (URL) throws -> Value) throws -> Value {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LittleSwitch Tooling \(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

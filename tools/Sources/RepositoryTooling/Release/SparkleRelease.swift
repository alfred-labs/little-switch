package struct SparkleRelease: Sendable {
    package let version: String
    package let build: String
    package let length: UInt64
    package let signature: String

    package init(version: String, build: String, length: UInt64, signature: String) {
        self.version = version
        self.build = build
        self.length = length
        self.signature = signature
    }
}

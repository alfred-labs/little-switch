import Foundation
import LittleSwitchCore

extension TrafficLogStore {
    public struct Configuration: Equatable, Sendable {
        public var directory: URL
        public var segmentByteLimit: Int
        public var maxSegments: Int
        public var maxAge: TimeInterval
        public var memoryByteLimit: Int

        public init(
            directory: URL,
            segmentByteLimit: Int = 10 * 1_024 * 1_024,
            maxSegments: Int = 40,
            maxAge: TimeInterval = 7 * 24 * 60 * 60,
            memoryByteLimit: Int = 50 * 1_024 * 1_024
        ) {
            self.directory = directory
            self.segmentByteLimit = max(1, segmentByteLimit)
            self.maxSegments = max(1, maxSegments)
            self.maxAge = max(0, maxAge)
            self.memoryByteLimit = max(1, memoryByteLimit)
        }

        public static var standard: Configuration {
            standard(
                applicationSupportDirectory: FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        }

        package static func standard(
            applicationSupportDirectory: URL?,
            homeDirectory: URL
        ) -> Configuration {
            let base = applicationSupportDirectory ?? homeDirectory
            return Configuration(
                directory:
                    base
                    .appendingPathComponent(
                        ProductIdentity.applicationSupportDirectoryName,
                        isDirectory: true
                    )
                    .appendingPathComponent("Logs", isDirectory: true)
            )
        }
    }

    package static func remainingMemoryBytes(_ total: Int, removing bytes: Int?) -> Int {
        max(0, total - (bytes ?? 0))
    }
}

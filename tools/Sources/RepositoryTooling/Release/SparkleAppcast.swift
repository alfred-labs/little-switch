import Foundation

package enum SparkleAppcast {
    package static func publicationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    package static func enclosureURL(version: String) -> String {
        "https://github.com/alfred-labs/little-switch/releases/download/v\(version)/LittleSwitch-\(version)-arm64.dmg"
    }

    package static func items(in source: String) -> [String] {
        source.matches(of: #/[ \t]*<item>[\s\S]*?</item>/#).map { String($0.output) }
    }

    package static func render(
        _ release: SparkleRelease,
        publicationDate: String,
        description: String,
        previous: String = "",
        replacing versionToReplace: String? = nil
    ) -> String {
        let version = release.version
        let description = description.isEmpty ? "<h2>LittleSwitch \(AppcastHTML.escape(version))</h2>" : description
        let enclosure =
            "<enclosure url=\"\(AppcastHTML.escape(enclosureURL(version: version)))\" length=\"\(release.length)\" "
            + "type=\"application/octet-stream\" sparkle:edSignature=\"\(AppcastHTML.escape(release.signature))\"/>"
        let item = """
                    <item>
                        <title>\(AppcastHTML.escape(version))</title>
                        <pubDate>\(AppcastHTML.escape(publicationDate))</pubDate>
                        <link>https://raw.githubusercontent.com/alfred-labs/little-switch/main/packaging/appcast.xml</link>
                        <sparkle:version>\(AppcastHTML.escape(release.build))</sparkle:version>
                        <sparkle:shortVersionString>\(AppcastHTML.escape(version))</sparkle:shortVersionString>
                        <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                        <description><![CDATA[\(description.replacingOccurrences(of: "]]>", with: "]]&gt;"))]]></description>
                        \(enclosure)
                    </item>
            """
        let previousItems = items(in: previous).filter { item in
            guard let versionToReplace else { return true }
            return !item.contains("/download/v\(versionToReplace)/")
        }
        return """
            <?xml version="1.0" encoding="utf-8" standalone="yes"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
                <channel>
                    <title>LittleSwitch</title>
                    <link>https://raw.githubusercontent.com/alfred-labs/little-switch/main/packaging/appcast.xml</link>
                    <description>LittleSwitch releases</description>
            \(([item] + previousItems).joined(separator: "\n"))
                </channel>
            </rss>

            """
    }
}

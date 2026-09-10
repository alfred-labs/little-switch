import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Sparkle release appcast")
struct SparkleAppcastTests {
    @Test("A fixed date uses the RFC 822 UTC representation")
    func fixedDate() {
        #expect(
            SparkleAppcast.publicationDate(Date(timeIntervalSince1970: 1_788_372_000))
                == "Wed, 02 Sep 2026 18:00:00 +0000")
        #expect(
            SparkleAppcast.enclosureURL(version: "0.1.1")
                == "https://github.com/alfred-labs/little-switch/releases/download/v0.1.1/LittleSwitch-0.1.1-arm64.dmg"
        )
    }

    @Test("The full document escapes every scalar, protects CDATA and preserves item order")
    func document() {
        let previous = "<rss>\n  <item>older</item>\n\t<item>oldest</item>\n</rss>"
        let result = SparkleAppcast.render(
            .init(version: "1&2", build: "3<4", length: 42, signature: "s\"'"),
            publicationDate: "fixed & date",
            description: "ends with ]]>",
            previous: previous)
        #expect(
            result == """
                <?xml version="1.0" encoding="utf-8" standalone="yes"?>
                <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
                    <channel>
                        <title>LittleSwitch</title>
                        <link>https://raw.githubusercontent.com/alfred-labs/little-switch/main/packaging/appcast.xml</link>
                        <description>LittleSwitch releases</description>
                        <item>
                            <title>1&amp;2</title>
                            <pubDate>fixed &amp; date</pubDate>
                            <link>https://raw.githubusercontent.com/alfred-labs/little-switch/main/packaging/appcast.xml</link>
                            <sparkle:version>3&lt;4</sparkle:version>
                            <sparkle:shortVersionString>1&amp;2</sparkle:shortVersionString>
                            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
                            <description><![CDATA[ends with ]]&gt;]]></description>
                            <enclosure url="https://github.com/alfred-labs/little-switch/releases/download/v1&amp;2/LittleSwitch-1&amp;2-arm64.dmg" length="42" type="application/octet-stream" sparkle:edSignature="s&quot;&apos;"/>
                        </item>
                  <item>older</item>
                \t<item>oldest</item>
                    </channel>
                </rss>

                """)
        #expect(SparkleAppcast.items(in: previous) == ["  <item>older</item>", "\t<item>oldest</item>"])
    }

    @Test("Republishing removes only the requested version and supplies default notes")
    func replacement() {
        let retained = " <item>/download/v0.1.0/</item>"
        let previous = "<item>/download/v0.1.1/</item>\n" + retained
        let result = SparkleAppcast.render(
            .init(version: "0.1.1", build: "2", length: 1, signature: "new"),
            publicationDate: "date",
            description: "",
            previous: previous,
            replacing: "0.1.1")
        #expect(SparkleAppcast.items(in: result).count == 2)
        #expect(SparkleAppcast.items(in: result).last == retained)
        #expect(result.contains("<![CDATA[<h2>LittleSwitch 0.1.1</h2>]]>"))
        #expect(SparkleAppcast.items(in: "").isEmpty)
    }
}

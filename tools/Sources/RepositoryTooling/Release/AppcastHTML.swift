import Foundation

package enum AppcastHTML {
    // Keep the previous JavaScript trim semantics, including BOM but excluding U+0085.
    private static let noteWhitespace = CharacterSet(
        charactersIn: "\t\n\u{000B}\u{000C}\r \u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}"
            + "\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}"
            + "\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    package static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    package static func markdown(_ source: String) -> String {
        var blocks: [String] = []
        var list: [String] = []
        func closeList() {
            if !list.isEmpty {
                blocks.append("<ul>" + list.joined() + "</ul>")
                list.removeAll(keepingCapacity: true)
            }
        }
        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: noteWhitespace)
            if line.isEmpty {
                closeList()
            } else if line.utf8.starts(with: "- ".utf8) {
                list.append("<li>\(inline(String(line.unicodeScalars.dropFirst(2))))</li>")
            } else if line.utf8.starts(with: "## ".utf8) {
                closeList()
                blocks.append("<h2>\(escape(String(line.unicodeScalars.dropFirst(3))))</h2>")
            } else {
                closeList()
                blocks.append("<p>\(inline(line))</p>")
            }
        }
        closeList()
        return blocks.joined(separator: "\n")
    }

    private static func inline(_ text: String) -> String {
        escape(text).replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
    }
}

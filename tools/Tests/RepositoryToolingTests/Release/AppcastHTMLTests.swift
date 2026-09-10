import Testing

@testable import RepositoryTooling

@Suite("Sparkle release notes")
struct AppcastHTMLTests {
    @Test("Markup and attribute delimiters are escaped")
    func escaping() {
        #expect(AppcastHTML.escape("<a href=\"x\">&'") == "&lt;a href=&quot;x&quot;&gt;&amp;&apos;")
        #expect(AppcastHTML.escape("plain") == "plain")
    }

    @Test("Headings, lists, paragraphs and bold text produce the existing safe HTML subset")
    func markdown() {
        let source = """
            ## Live <remaps>

            - **Applies immediately**, even with <running> apps
            - Catalog stays invariant

            A **plain** paragraph & **another**.
            - Last list
            ## Next heading
            - Another list
            Final paragraph.
            """
        let expected = """
            <h2>Live &lt;remaps&gt;</h2>
            <ul><li><strong>Applies immediately</strong>, even with &lt;running&gt; apps</li><li>Catalog stays invariant</li></ul>
            <p>A <strong>plain</strong> paragraph &amp; <strong>another</strong>.</p>
            <ul><li>Last list</li></ul>
            <h2>Next heading</h2>
            <ul><li>Another list</li></ul>
            <p>Final paragraph.</p>
            """
        #expect(AppcastHTML.markdown(source) == expected)
        #expect(
            AppcastHTML.markdown("- Ends with a list\r\n- **Bold**")
                == "<ul><li>Ends with a list</li><li><strong>Bold</strong></li></ul>")
        #expect(AppcastHTML.markdown(" \r\n\t").isEmpty)
    }

    @Test("Release notes preserve the original Unicode whitespace and prefix rules")
    func unicodeNotes() {
        #expect(AppcastHTML.markdown("\u{FEFF}## Heading\u{FEFF}") == "<h2>Heading</h2>")
        #expect(AppcastHTML.markdown("\u{0085}text\u{0085}") == "<p>\u{0085}text\u{0085}</p>")
        #expect(AppcastHTML.markdown("- \u{0301}mark") == "<ul><li>\u{0301}mark</li></ul>")
        #expect(AppcastHTML.markdown("## \u{0301}mark") == "<h2>\u{0301}mark</h2>")
    }
}

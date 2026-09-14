public enum TrafficDiagnosticText {
    /// Bound by scalars rather than graphemes so combining characters cannot
    /// turn a single diagnostic field into an unbounded retained payload.
    public static func bounded(_ value: String, limit: Int = 512) -> String {
        let limit = max(0, limit)
        let prefix = value.unicodeScalars.prefix(limit)
        let text = String(String.UnicodeScalarView(prefix))
        return value.unicodeScalars.dropFirst(limit).isEmpty ? text : text + "…"
    }
}

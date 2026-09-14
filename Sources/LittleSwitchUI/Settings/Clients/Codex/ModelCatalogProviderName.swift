enum ModelCatalogProviderName {
    /// Style plain lowercase labels without changing brand casing or technical names.
    static func title(_ name: String) -> String {
        guard name == name.lowercased(),
            name.allSatisfy({ $0.isLetter || $0.isWhitespace }),
            let first = name.first,
            first.isLetter
        else { return name }
        return first.uppercased() + name.dropFirst()
    }
}

/// Domain and locale filters the search bridge forwards when the request
/// carries them.
package struct WebSearchFilterOptions: Equatable, Sendable {
    let includeDomains: [String]?
    let excludeDomains: [String]?
    let location: String?
    let country: String?

    package init(
        includeDomains: [String]? = nil,
        excludeDomains: [String]? = nil,
        location: String? = nil,
        country: String? = nil
    ) {
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
        self.location = location
        self.country = country
    }
}

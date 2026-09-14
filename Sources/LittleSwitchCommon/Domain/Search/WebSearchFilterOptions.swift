/// Domain and locale filters the search bridge forwards when the request
/// carries them.
package struct WebSearchFilterOptions: Equatable, Sendable {
    package let includeDomains: [String]?
    package let excludeDomains: [String]?
    package let location: String?
    package let country: String?

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

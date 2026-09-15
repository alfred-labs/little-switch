import Foundation

/// Creates UI copy from the module's string catalog.
enum L10n {
    static func imageProbeProgress(completed: Int, total: Int, locale: Locale = .current) -> String {
        string("Checking image support: \(completed)/\(total)", locale: locale)
    }

    static func resource(
        _ value: String.LocalizationValue,
        locale: Locale = .current,
        comment: StaticString? = nil
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            value,
            locale: locale,
            bundle: Bundle.module,
            comment: comment
        )
    }

    static func string(
        _ value: String.LocalizationValue,
        locale: Locale = .current,
        comment: StaticString? = nil
    ) -> String {
        String(localized: resource(value, locale: locale, comment: comment))
    }
}

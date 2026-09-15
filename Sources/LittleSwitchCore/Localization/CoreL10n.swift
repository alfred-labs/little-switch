import Foundation

/// Creates user-facing Core error copy from the module's string catalog.
package enum CoreL10n {
    package static func string(
        _ value: String.LocalizationValue,
        locale: Locale = .current
    ) -> String {
        String(
            localized: LocalizedStringResource(
                value,
                locale: locale,
                bundle: Bundle.module
            )
        )
    }
}

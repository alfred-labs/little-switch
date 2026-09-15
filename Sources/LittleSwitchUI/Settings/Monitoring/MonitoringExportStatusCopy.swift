import LittleSwitchCommon

enum MonitoringExportStatusCopy {
    static func message(
        for status: MonitoringSignalExportStatus
    ) -> String? {
        if let issue = status.configurationIssue {
            return message(for: issue)
        }
        if let failure = status.failure {
            return message(for: failure)
        }
        if let warning = status.warning {
            return message(for: warning)
        }
        return nil
    }

    static func message(for warning: MonitoringExportWarning) -> String {
        switch warning {
        case .partialRejection:
            L10n.string("The receiver accepted the batch with some rejected items.")
        case .receiverWarning:
            L10n.string("The receiver accepted the batch with a warning.")
        case .deliveryUncertain:
            L10n.string("The interrupted batch may already have reached the receiver.")
        }
    }

    static func message(for issue: MonitoringExportConfigurationIssue) -> String {
        switch issue {
        case .invalidInterval:
            L10n.string("Choose an export interval between 5 and 300 seconds.")
        case .invalidEndpoint:
            L10n.string("Enter a valid receiver URL.")
        case .missingCredential:
            L10n.string("The receiver's saved token is missing or invalid.")
        }
    }

    static func message(for failure: OTLPExportFailure) -> String {
        switch failure {
        case .httpStatus(let status):
            L10n.string("The receiver returned HTTP \(status).")
        case .invalidResponse:
            L10n.string("The receiver did not return a valid OTLP acknowledgement.")
        case .responseTooLarge:
            L10n.string("The receiver's response exceeded the size limit.")
        case .network:
            L10n.string("The receiver could not be reached.")
        case .tls:
            L10n.string("The receiver's secure connection could not be verified.")
        case .invalidEndpoint:
            L10n.string("Enter a valid receiver URL.")
        case .credential:
            L10n.string("The receiver's saved token is missing or invalid.")
        }
    }

    static func message(for outcome: MonitoringExportTestOutcome) -> String {
        switch outcome {
        case .disabled:
            L10n.string("Disabled")
        case .accepted:
            L10n.string("Accepted")
        case .partial(let rejected):
            L10n.string("Accepted with \(rejected) rejected items.")
        case .warning:
            L10n.string("Accepted with a receiver warning.")
        case .retrying(let failure):
            L10n.string("Retry scheduled. \(message(for: failure))")
        case .failed(let failure):
            message(for: failure)
        case .invalidConfiguration(let issue):
            message(for: issue)
        case .cancelled:
            L10n.string("The test was interrupted; delivery is uncertain.")
        }
    }
}

import LittleSwitchCommon
import Testing

@testable import LittleSwitchUI

@Suite("Monitoring export status copy")
struct MonitoringExportStatusCopyTests {
    @Test("A delivery failure takes priority over a receiver warning until it is cleared")
    func failureAndWarningPriority() {
        var status = MonitoringSignalExportStatus(failure: .network, warning: .partialRejection)
        #expect(
            MonitoringExportStatusCopy.message(for: status)
                == L10n.string("The receiver could not be reached."))
        status.failure = nil
        #expect(
            MonitoringExportStatusCopy.message(for: status)
                == L10n.string("The receiver accepted the batch with some rejected items."))
        status.warning = nil
        #expect(MonitoringExportStatusCopy.message(for: status) == nil)
    }

    @Test("Every monitoring export state has localized product copy")
    func everyStateHasLocalizedProductCopy() {
        let warnings: [MonitoringExportWarning] = [
            .partialRejection,
            .receiverWarning,
            .deliveryUncertain,
        ]
        let issues: [MonitoringExportConfigurationIssue] = [
            .invalidInterval,
            .invalidEndpoint,
            .missingCredential,
        ]
        let failures: [OTLPExportFailure] = [
            .httpStatus(503),
            .invalidResponse,
            .responseTooLarge,
            .network,
            .tls,
            .invalidEndpoint,
            .credential,
        ]

        for warning in warnings {
            #expect(!MonitoringExportStatusCopy.message(for: warning).isEmpty)
        }
        for issue in issues {
            #expect(!MonitoringExportStatusCopy.message(for: issue).isEmpty)
        }
        for failure in failures {
            #expect(!MonitoringExportStatusCopy.message(for: failure).isEmpty)
        }
    }

    @Test("Monitoring test outcomes compose localized copy")
    func monitoringTestOutcomesComposeLocalizedCopy() {
        let outcomes: [MonitoringExportTestOutcome] = [
            .disabled,
            .accepted,
            .partial(rejected: 2),
            .warning,
            .retrying(.network),
            .failed(.httpStatus(500)),
            .invalidConfiguration(.missingCredential),
            .cancelled,
        ]

        for outcome in outcomes {
            #expect(!MonitoringExportStatusCopy.message(for: outcome).isEmpty)
        }
    }
}

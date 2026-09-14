import Foundation
import LittleSwitchCommon
import Testing

@testable import LittleSwitchCore

@Suite("Monitoring Prometheus and OpenMetrics exposition")
struct MonitoringExpositionTests {
    @Test("Specific charset exclusions take precedence over generic media ranges")
    func charsetExclusion() {
        for media in ["text/plain", "application/openmetrics-text"] {
            #expect(MonitoringMetricsTextEncoder.negotiate(accept: ["\(media);charset=utf-8;q=0,\(media);q=1"]) == nil)
        }
    }

    @Test("Counter family metadata differs from its OpenMetrics sample suffix")
    func counterNames() async {
        let store = MonitoringStore()
        await store.recordAdmission(.timedOut)
        let snapshot = await store.snapshot()
        #expect(
            MonitoringMetricsTextEncoder.encode(snapshot, format: .prometheus) == """
                # HELP littleswitch_gateway_admission_timeouts_total Requests that timed out waiting for provider admission.
                # TYPE littleswitch_gateway_admission_timeouts_total counter
                littleswitch_gateway_admission_timeouts_total 1

                """)
        #expect(
            MonitoringMetricsTextEncoder.encode(snapshot, format: .openMetrics) == """
                # HELP littleswitch_gateway_admission_timeouts Requests that timed out waiting for provider admission.
                # TYPE littleswitch_gateway_admission_timeouts counter
                littleswitch_gateway_admission_timeouts_total 1
                # EOF

                """)
    }

    @Test("Histograms expose cumulative buckets including infinity and exact observed count")
    func histogramBuckets() async {
        let store = MonitoringStore()
        for duration in [0.05, 0.1, 0.3] {
            await store.finish(
                MonitoringObservation(
                    requestID: UUID(),
                    finishedAt: Date(),
                    durationSeconds: duration,
                    client: .claude,
                    route: .messages,
                    outcome: .success))
        }
        let text = MonitoringMetricsTextEncoder.encode(await store.snapshot())
        let buckets = text.split(separator: "\n").filter {
            $0.hasPrefix("littleswitch_gateway_request_duration_seconds_bucket{")
        }
        #expect(buckets.count == 13)
        #expect(
            buckets.first
                == #"littleswitch_gateway_request_duration_seconds_bucket{client="claude",le="0.05",outcome="success",provider_id="unknown",route="messages"} 1"#
        )
        #expect(buckets[1].hasSuffix(" 2"))
        #expect(buckets[2].hasSuffix(" 2"))
        #expect(buckets[3].hasSuffix(" 3"))
        #expect(buckets.last?.contains(#"le="+Inf""#) == true)
        #expect(buckets.last?.hasSuffix(" 3") == true)
        #expect(!text.contains("model="))
    }

    @Test("Accept negotiation honors quality, versions, wildcards and exclusions")
    func negotiate() {
        let cases: [([String], MonitoringMetricsFormat?)] = [
            ([], .prometheus), (["*/*"], .prometheus), (["text/*"], .prometheus),
            (["application/openmetrics-text; version=1.0.0"], .openMetrics),
            (["application/openmetrics-text;version=1.0.0;q=0.9", "text/plain;q=0.5"], .openMetrics),
            (["application/openmetrics-text;q=0", "text/plain;q=1"], .prometheus),
            (["application/openmetrics-text;version=0.0.1"], nil),
            (["text/plain;version=0.0.3"], nil), (["application/json"], nil),
            (["*/*;q=0"], nil), (["text/plain;q=0,*/*;q=1"], nil),
            (["application/openmetrics-text;q=0.5,text/plain;q=0.5"], .prometheus),
            (["application/openmetrics-text;q=bogus"], nil),
            (["application/openmetrics-text;q=1.1"], nil),
            ([";"], nil), (["text/plain;q"], nil), (["text/plain;q=1;q=0"], nil),
            (["text/plain;charset=iso-8859-1"], nil),
        ]
        for (headers, expected) in cases {
            #expect(MonitoringMetricsTextEncoder.negotiate(accept: headers) == expected)
        }
        #expect(MonitoringMetricsFormat.prometheus.contentType == "text/plain; version=0.0.4; charset=utf-8")
        #expect(
            MonitoringMetricsFormat.openMetrics.contentType
                == "application/openmetrics-text; version=1.0.0; charset=utf-8")
    }

    @Test("Escaping preserves arbitrary UTF8 without allowing injected label syntax")
    func escaping() {
        #expect(MonitoringMetricsTextEncoder.escape("quote\" slash\\ line\n猫") == "quote\\\" slash\\\\ line\\n猫")
    }
}

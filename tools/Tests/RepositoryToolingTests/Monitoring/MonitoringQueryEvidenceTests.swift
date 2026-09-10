import Foundation
import Testing

@testable import RepositoryTooling

@Suite("Monitoring query evidence")
struct MonitoringQueryEvidenceTests {
    @Test(
        "Metric evidence requires one successful result whose sample is the string one",
        arguments: [
            "{}", "[]", #"{"status":"error","data":{"result":[{"value":[0,"1"]}]}}"#,
            #"{"status":"success","data":{}}"#, #"{"status":"success","data":{"result":[]}}"#,
            #"{"status":"success","data":{"result":[{},{}]}}"#,
            #"{"status":"success","data":{"result":[{}]}}"#,
            #"{"status":"success","data":{"result":[{"value":[0]}]}}"#,
            #"{"status":"success","data":{"result":[{"value":[0,1]}]}}"#,
            #"{"status":"success","data":{"result":[{"value":[0,"0"]}]}}"#,
        ])
    func missingMetric(body: String) throws {
        #expect(try !MonitoringQueryEvidence.metrics(Data(body.utf8)))
    }

    @Test(
        "Log evidence requires the exact synthetic body in any successful stream",
        arguments: [
            "{}", "[]", #"{"status":"error","data":{"result":[]}}"#,
            #"{"status":"success","data":{}}"#, #"{"status":"success","data":{"result":[]}}"#,
            #"{"status":"success","data":{"result":[{}, {"values":[]} ]}}"#,
            #"{"status":"success","data":{"result":[{"values":[[],["0"],["0",1],["0","monitoring.tests"]]}]}}"#,
        ])
    func missingLog(body: String) throws {
        #expect(try !MonitoringQueryEvidence.logs(Data(body.utf8)))
    }

    @Test("A match in a later log stream is accepted")
    func laterStream() throws {
        let body =
            #"{"status":"success","data":{"result":[{}, {"values":[["0","unrelated"],["1","monitoring.test"]]}]}}"#
        #expect(try MonitoringQueryEvidence.logs(Data(body.utf8)))
    }

    @Test("Malformed JSON is rejected for either signal", arguments: [false, true])
    func malformed(logs: Bool) throws {
        #expect(throws: (any Error).self) {
            _ =
                try logs
                ? MonitoringQueryEvidence.logs(Data("{".utf8)) : MonitoringQueryEvidence.metrics(Data("{".utf8))
        }
    }
}

import Foundation

package struct MonitoringReadiness: Sendable {
    private let client: any MonitoringHTTPClient
    private let sleep: MonitoringSleep

    package init(client: any MonitoringHTTPClient, sleep: @escaping MonitoringSleep) {
        self.client = client
        self.sleep = sleep
    }

    package func run(emit: MonitoringOutput) async throws {
        for (name, endpoint) in [
            ("Prometheus", "http://127.0.0.1:19090/-/ready"),
            ("Loki", "http://127.0.0.1:13100/ready"),
        ] {
            let request = URLRequest(url: try URL(endpoint, strategy: .url), timeoutInterval: 2)
            var ready = false
            for _ in 0..<45 {
                try Task.checkCancellation()
                do {
                    let response = try await client.send(request)
                    if (200..<300).contains(response.status) {
                        ready = true
                        break
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // A receiver may still be starting or have not bound its published port.
                }
                try await sleep(.seconds(1))
            }
            guard ready else { throw MonitoringFailure.notReady(name) }
            await emit("\(name) ready")
        }
    }
}

# Monitoring

LittleSwitch exposes local metrics and structured metadata logs, and pushes both
independently over OTLP/HTTP JSON. Configure them in **Settings → Monitoring**.
This implementation uses Foundation networking and does not add an OpenTelemetry
SDK or a gRPC dependency.

## Settings

**Local access** has one row for metrics and one for logs. Use **Copy URL** to
choose the complete HTTP or HTTPS address. Copy is available once the local
endpoint is enabled in the applied settings. HTTPS also requires the running
listener's identity and local trust.

**OTLP export** contains separate Metrics and Logs disclosures. Turning an export
on opens its settings. An inactive destination can also be opened to prepare it.
Folding a destination keeps the values entered on the page. Enter the complete
receiver URL, choose authentication, then set the metrics interval or log level.
Leave a token field blank to keep its saved token, or use **Remove saved token**
to remove it on Apply. Non-secret edits survive navigation. Typed tokens do not.

Use **Apply** or **Command-S** to persist the page. **Test export**, beside Apply,
sends a synthetic event with the applied settings. Apply pending changes before
testing. Each signal shows its own delivery state and any controlled error. Delivery details expose the queue and retry information.

## Local endpoints

`GET http://127.0.0.1:11436/metrics` is enabled by default. It negotiates Prometheus
text (`text/plain; version=0.0.4`) or OpenMetrics 1.0 using `Accept`. Unsupported
formats return 406. `GET /logs` is disabled by default and returns a JSON page when
enabled. Both routes use `Cache-Control: no-store`, permit only GET (405 otherwise),
and return 404 when disabled. The existing Host/Origin policy is checked first.
They never count their own requests or create traffic captures.

HTTPS uses the same port and existing sniffer, identity and trust. The settings page
shows HTTPS only when the running listener has an identity and the local trust is
present. Opening Monitoring or copying an endpoint does not install a certificate.

The log page contains `entries`, `nextCursor` and `retentionLost`. Filters are
`since` (RFC3339), `level` (info/warn/error), `request_id` (UUID), and `limit` (1–500, default 100). Pass `cursor` from the previous page to continue with its original
filters. Malformed or conflicting parameters return 400. A cursor whose retained
position was lost returns 410. A `since` query reports `retentionLost` when history
was evicted. This is a LittleSwitch read API, not a standardized logs endpoint.

Local logs retain at most 1,000 entries and 2 MiB. Each entry is limited to 4 KiB,
and a response to 1 MiB. They contain closed event names, request/event IDs, dates,
client, route, provider ID, outcome, status, bounded resolved model and usage.
They cannot include headers, tokens, prompts, response bodies, tool arguments or
free-form remote errors. Detailed diagnostic captures remain a separate local
facility with their own retention and sensitivity.

## Metrics

| Prometheus name | Type | Meaning |
| --- | --- | --- |
| `littleswitch_gateway_requests_total` | Counter | Terminal gateway requests by outcome. |
| `littleswitch_gateway_tokens_total` | Counter | Reported input/output/cache tokens, by kind. |
| `littleswitch_gateway_estimated_input_tokens_total` | Counter | Locally estimated input, kept separate from reported usage. |
| `littleswitch_gateway_request_duration_seconds` | Histogram | Request lifetime including the response stream. |
| `littleswitch_gateway_requests_in_flight` | Gauge | Current gateway requests. |
| `littleswitch_provider_requests_waiting` | Gauge | Requests awaiting provider admission. |
| `littleswitch_gateway_admission_rejections_total` | Counter | Admission rejections by controlled reason. |
| `littleswitch_gateway_admission_timeouts_total` | Counter | Admission wait timeouts. |
| `littleswitch_gateway_web_searches_total` | Counter | Executed web searches by outcome. |
| `littleswitch_monitoring_dropped_total` | Counter | Monitoring losses by signal and reason. |
| `littleswitch_monitoring_test` | Gauge | Synthetic test marker, value 1. |

Each family uses only its relevant bounded labels (client, route, provider ID,
outcome, token kind or loss reason). Request IDs and model names are never metric
labels. Families have at most 2,048 series, including a stable overflow series.
Histograms use second boundaries 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60,
120, 300 and +Inf. Missing provider usage does not become an invented zero token
report. Repeated cumulative usage in one exchange is counted once, while distinct
upstream model exchanges are added.

OTLP uses dotted names (`littleswitch.gateway.requests`, for example), resource
attributes `service.name=littleswitch`, `service.version` and `service.instance.id`,
and cumulative counters/histograms with stable process start times. An app restart
creates a new instance. Choose push or scrape for a given destination to avoid
double ingestion of the same measurements.

## OTLP destinations and delivery

Supply the complete HTTP(S) URL for each signal. No path is appended or rewritten.
Plain HTTP is accepted only for literal loopback IPs or `localhost`. Remote
destinations require HTTPS with normal certificate and hostname verification.
Redirects are not followed. URLs cannot contain credentials, a query or a fragment.
The two destinations have independent None/Bearer authentication, tokens and status.

Metrics export every 5–300 seconds (default 15) and retain the latest cumulative
snapshot. Successful export never resets totals. Logs flush within two seconds or
at 256 entries. Payloads are limited to 512 KiB. Metrics split at complete data
points. Logs use a 5,000 entry / 5 MiB queue and expire after five minutes. Queues
are in memory and include an active send in their limits.

An export has a five-second total deadline and a 1 MiB decoded response limit.
429/502/503/504 and transient network failures retry with backoff. `Retry-After`
is respected even beyond 30 seconds. Otherwise the jittered delay is capped at
30 seconds. Certificate errors and other HTTP failures are permanent. A partial
success removes the lot, counts only declared rejections, and is not replayed.
Statuses use controlled messages, not remote response text.

Apply validates both destinations before persisting anything, stages replacement
tokens under new Keychain accounts, saves configuration, and then changes exporter
generations. Old requests are cancelled and joined before old tokens are retired.
Unsent logs are not moved to a new destination. Disabling export does not disable
local collection. On reactivation, metrics retain process totals. Logs begin with
new events. Shutdown gives the final flush two seconds.

Delivery is not exactly once: cancellation or a lost acknowledgement can leave
remote acceptance uncertain. Retried logs retain their event ID for downstream
deduplication. **Accepted** acknowledges receiver acceptance. Query the backend to
verify indexing. **Test export** uses the same production pipeline and does not
create an AI request.

## Prometheus and Loki lab

The Compose project publishes only loopback ports, uses ARM64 images and ephemeral
storage, and has no Prometheus scrape jobs. Its complete destinations are:

- Metrics: `http://127.0.0.1:19090/api/v1/otlp/v1/metrics`
- Logs: `http://127.0.0.1:13100/otlp/v1/logs`

```sh
docker compose -f tools/monitoring/compose.yaml up -d
mise run monitoring:integration
docker compose -f tools/monitoring/compose.yaml down
```

The opt-in Swift suite verifies production encoders and transport by querying the
synthetic data in both backends. The separate `mise run monitoring:probe`
checks raw receiver JSON compatibility. See the [validation journal](troubleshoots/monitoring-validation.md)
for commands and observed receiver responses.

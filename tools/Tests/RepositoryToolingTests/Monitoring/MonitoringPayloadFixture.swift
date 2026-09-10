enum MonitoringPayloadFixture {
    static let metrics = #"""
        {"resourceMetrics":[{
          "resource":{"attributes":[
            {"key":"service.name","value":{"stringValue":"littleswitch"}},
            {"key":"service.instance.id","value":{"stringValue":"00000000-0000-4000-8000-000000000001"}}
          ]},
          "scopeMetrics":[{
            "scope":{"name":"littleswitch.monitoring.probe"},
            "metrics":[{"name":"littleswitch_monitoring_probe","sum":{
              "aggregationTemporality":2,"isMonotonic":true,"dataPoints":[{
                "attributes":[{"key":"probe_id","value":{"stringValue":"00000000-0000-4000-8000-000000000001"}}],
                "timeUnixNano":"1782345678123000000","startTimeUnixNano":"1782345677123000000","asInt":"1"
              }]
            }}]
          }]
        }]}
        """#

    static let logs = #"""
        {"resourceLogs":[{
          "resource":{"attributes":[
            {"key":"service.name","value":{"stringValue":"littleswitch"}},
            {"key":"service.instance.id","value":{"stringValue":"00000000-0000-4000-8000-000000000001"}}
          ]},
          "scopeLogs":[{
            "scope":{"name":"littleswitch.monitoring.probe"},
            "logRecords":[{
              "timeUnixNano":"1782345678123000000","observedTimeUnixNano":"1782345678123000000",
              "severityNumber":9,"severityText":"INFO","body":{"stringValue":"monitoring.test"},
              "attributes":[{"key":"event.id","value":{"stringValue":"00000000-0000-4000-8000-000000000001"}}]
            }]
          }]
        }]}
        """#
}

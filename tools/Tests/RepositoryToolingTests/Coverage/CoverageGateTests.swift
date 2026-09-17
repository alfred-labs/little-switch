import Testing

@Suite("Coverage gate orchestration")
struct CoverageGateTests {
    @Test(
        "Every per-target test bundle is passed as a coverage object in both reports",
        arguments: CoverageGateFixture.Package.allCases)
    func multipleTestBundles(package: CoverageGateFixture.Package) throws {
        var fixture = CoverageGateFixture()
        fixture.additionalTestProducts = ["Secondary coverageTests"]
        let (result, log) = try fixture.run(package: package)
        #expect(result.status == 0, "\(result.stdout)\n\(result.stderr)")
        let reports = log.split(separator: "\n").filter { $0.hasPrefix("llvm-cov\t") }
        #expect(reports.count == 2)
        for report in reports {
            let objects = report.split(separator: "\t").filter { $0.hasPrefix("-object=") }
            let suffix = "Secondary coverageTests.xctest/Contents/MacOS/Secondary coverageTests"
            #expect(objects.count == 1)
            #expect(objects.first?.hasSuffix(suffix) == true)
        }
    }

    @Test(
        "Both packages use current SwiftPM artifacts, a strict build and atomic profile counters",
        arguments: CoverageGateFixture.Package.allCases)
    func currentArtifacts(package: CoverageGateFixture.Package) throws {
        let (result, log) = try CoverageGateFixture().run(package: package)
        #expect(result.status == 0, "\(result.stdout)\n\(result.stderr)")
        #expect(log.contains("swift\tswift\tbuild\t--show-bin-path"))
        #expect(
            package == .app
                ? log.contains(
                    "--enable-code-coverage\t--disable-xctest\t--toolset\ttools/ci/appkit-coverage-test-runner.json\t--no-parallel"
                )
                : log.contains("--enable-code-coverage\t--no-parallel"))
        #expect(log.contains("-warnings-as-errors"))
        #expect(log.contains("-instrprof-atomic-counter-update-all"))
        #expect(log.contains(package == .app ? ".build/coverage" : ".build/tooling-coverage"))
        #expect(!log.contains(".build/arm64-apple-macosx"))
    }

    @Test(
        "Measured arguments preserve spaces and shell characters while raw reports include excluded adapters",
        arguments: CoverageGateFixture.Package.allCases)
    func exactScope(package: CoverageGateFixture.Package) throws {
        let source = "Sources/App/A $(touch injected) name.swift"
        var fixture = CoverageGateFixture()
        fixture.sources = [source, "Sources/App/B.swift", "Sources/App/Excluded.swift"]
        fixture.exclusions = "Sources/App/Excluded.swift\tnative adapter fixture\n"
        fixture.measuredReport = CoverageFixture.report([
            ("App/A $(touch injected) name.swift", "100.00%"), ("App/B.swift", "100.00%"),
        ])
        fixture.rawReport = CoverageFixture.report([("App/Excluded.swift", "0.00%")], total: "66.67%")
        let (result, log) = try fixture.run(package: package)
        #expect(result.status == 0, "\(result.stdout)\n\(result.stderr)")
        let prefix = package == .app ? "" : "tools/"
        let measured = try #require(log.split(separator: "\n").first { $0.contains("$(touch injected)") })
        #expect(measured.contains("\t" + prefix + source + "\t" + prefix + "Sources/App/B.swift"))
        #expect(!measured.contains("Excluded.swift"))
        #expect(log.contains("\t" + prefix + "Sources\t"))
        #expect(result.stdout.contains("(100.00% lines required)"))
        #expect(result.stdout.contains("(includes excluded adapters)"))
        #expect(result.stdout.contains("TOTAL 1 0 100.00% 1 0 100.00% 1 0 66.67%"))
    }

    @Test(
        "Measured report failures are surfaced by the shell gate",
        arguments: [
            (CoverageFixture.report([]), "Missing coverage row"),
            (
                CoverageFixture.report([("App/A.swift", "100.00%"), ("App/A.swift", "100.00%")]),
                "Duplicate coverage rows"
            ),
            (CoverageFixture.report([("App/A.swift", "99.00%")]), "line coverage must be exactly 100.00%; got 99.00%"),
            (CoverageFixture.report(total: "99.00%"), "Measured TOTAL line coverage must be exactly 100.00%"),
        ])
    func measuredFailures(value: (String, String)) throws {
        var fixture = CoverageGateFixture()
        fixture.measuredReport = value.0
        let (result, _) = try fixture.run()
        #expect(result.status != 0)
        #expect(result.stderr.contains(value.1))
    }

    @Test("Warnings are printed and rejected in both reports", arguments: [false, true])
    func warning(raw: Bool) throws {
        var fixture = CoverageGateFixture()
        if raw {
            fixture.rawWarning = "warning: fixture source is not linked"
        } else {
            fixture.measuredWarning = "warning: fixture source is not linked"
        }
        let (result, _) = try fixture.run()
        #expect(result.status != 0)
        #expect(result.stdout.contains("warning: fixture source is not linked"))
        #expect(result.stderr.contains("report contains an llvm-cov warning"))
    }

    @Test("Raw missing and duplicate totals fail the gate", arguments: ["", "TOTAL 0\nTOTAL 0\n"])
    func rawTotals(report: String) throws {
        var fixture = CoverageGateFixture()
        fixture.rawReport = report
        let (result, _) = try fixture.run()
        #expect(result.status != 0)
        #expect(result.stderr.contains("raw linked-source coverage TOTAL row"))
    }

    @Test("llvm-cov failure preserves its status and diagnostics", arguments: [false, true])
    func reportFailure(raw: Bool) throws {
        var fixture = CoverageGateFixture()
        if raw {
            fixture.rawStatus = 7
            fixture.rawReport = "raw llvm fixture failure"
        } else {
            fixture.measuredStatus = 7
            fixture.measuredReport = "measured llvm fixture failure"
        }
        let (result, _) = try fixture.run()
        #expect(result.status == 7)
        #expect(result.stderr.contains("llvm fixture failure"))
        #expect(result.stderr.contains("Failed to produce"))
    }

    @Test(
        "Missing current artifacts never fall back to stale outputs",
        arguments: ["CoverageTests", "default.profdata"])
    func missingArtifacts(name: String) throws {
        var fixture = CoverageGateFixture()
        fixture.missingArtifact = name
        let (result, log) = try fixture.run()
        #expect(result.status == 1)
        #expect(result.stderr.contains("not produced"))
        #expect(!log.contains("llvm-cov"))
    }

    @Test("A failed test run and empty measured scope stop before llvm-cov", arguments: [false, true])
    func prerequisites(testFailure: Bool) throws {
        var fixture = CoverageGateFixture()
        if testFailure { fixture.testStatus = 8 } else { fixture.sources = [] }
        let (result, log) = try fixture.run()
        #expect(result.status == (testFailure ? 8 : 1))
        #expect(!log.contains("llvm-cov"))
        if !testFailure { #expect(result.stderr.contains("no measured Swift sources")) }
    }
}

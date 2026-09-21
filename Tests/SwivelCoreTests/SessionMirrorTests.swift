import Foundation
import Testing
@testable import SwivelCore

@Suite("SessionMirror")
struct SessionMirrorTests {
    let home: URL

    init() {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swivel-mirror-test-\(UUID().uuidString)")
    }

    private func installScript(_ body: String) throws {
        let script = SessionMirror.scriptURL(home: home)
        try FileManager.default.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: home)
    }

    @Test func skipsWhenScriptMissing() {
        defer { cleanup() }
        #expect(SessionMirror.run(home: home) == .skipped)
    }

    @Test func skipsWhenInterpreterMissing() throws {
        defer { cleanup() }
        try installScript("pass\n")
        let missing = home.appendingPathComponent("no-such-python")
        #expect(SessionMirror.run(home: home, python: missing) == .skipped)
    }

    @Test func succeedsAndRunsAgainstGivenHome() throws {
        defer { cleanup() }
        try installScript("""
        import os, sys
        open(os.path.join(os.path.expanduser("~"), "ran"), "w").write(" ".join(sys.argv[1:]))
        """)
        #expect(SessionMirror.run(home: home) == .succeeded)
        let marker = home.appendingPathComponent("ran")
        #expect(try String(contentsOf: marker, encoding: .utf8) == "--quiet")
    }

    @Test func reportsNonZeroExit() throws {
        defer { cleanup() }
        try installScript("import sys\nsys.exit(3)\n")
        #expect(SessionMirror.run(home: home) == .failed(3))
    }

    @Test func timesOut() throws {
        defer { cleanup() }
        try installScript("import time\ntime.sleep(10)\n")
        #expect(SessionMirror.run(home: home, timeout: 0.5) == .timedOut)
        #expect(SessionMirror.loadRecord(home: home)?.kind == .timedOut)
    }

    @Test func recordsSummaryOnSuccess() throws {
        defer { cleanup() }
        try installScript("""
        print("cc-mirror-sessions: added 3, repaired 0, revived 0, pruned 0, flag-synced 1, retitled 0, t-retitled 0")
        """)
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(SessionMirror.run(home: home, now: { when }) == .succeeded)
        let record = try #require(SessionMirror.loadRecord(home: home))
        #expect(record.kind == .succeeded)
        #expect(record.at == when)
        #expect(record.changes == ["added 3", "flag-synced 1"])
    }

    @Test func quietRunWithoutChangesHasNoSummary() throws {
        defer { cleanup() }
        try installScript("pass\n")
        #expect(SessionMirror.run(home: home) == .succeeded)
        let record = try #require(SessionMirror.loadRecord(home: home))
        #expect(record.summary == nil)
        #expect(record.changes.isEmpty)
    }

    @Test func recordsSkipAndFailure() throws {
        defer { cleanup() }
        SessionMirror.run(home: home)
        #expect(SessionMirror.loadRecord(home: home)?.outcome == .skipped)
        try installScript("import sys\nsys.exit(3)\n")
        SessionMirror.run(home: home)
        #expect(SessionMirror.loadRecord(home: home)?.outcome == .failed(3))
    }

    @Test func missingRecordLoadsAsNil() {
        defer { cleanup() }
        #expect(SessionMirror.loadRecord(home: home) == nil)
    }
}

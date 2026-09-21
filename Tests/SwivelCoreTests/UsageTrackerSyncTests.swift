import Foundation
import Testing
@testable import SwivelCore

@Suite("UsageTrackerSync")
struct UsageTrackerSyncTests {
    private let profiles = [
        UsageTrackerSync.TrackerProfile(id: "E0B45AC9", name: "Personal"),
        UsageTrackerSync.TrackerProfile(id: "7D8E4458", name: "RAS")
    ]

    @Test func decodesIdAndName() throws {
        let json = """
        [{"id":"E0B45AC9","name":"Personal","organizationId":"379bc3cc","refreshInterval":300},
         {"id":"7D8E4458","name":"RAS","organizationId":"55b9ad9e"},
         {"name":"broken"}]
        """
        let decoded = UsageTrackerSync.decodeProfiles(Data(json.utf8))
        #expect(decoded == profiles)
    }

    @Test func decodesGarbageAsEmpty() {
        #expect(UsageTrackerSync.decodeProfiles(Data("not json".utf8)).isEmpty)
    }

    @Test func matchesByNameIgnoringCase() {
        #expect(UsageTrackerSync.resolve(swivelProfile: "ras", trackerProfiles: profiles)?.id == "7D8E4458")
        #expect(UsageTrackerSync.resolve(swivelProfile: "Personal", trackerProfiles: profiles)?.id == "E0B45AC9")
    }

    @Test func unmatchedNameResolvesToNil() {
        #expect(UsageTrackerSync.resolve(swivelProfile: "Work", trackerProfiles: profiles) == nil)
    }

    @Test func nameMapOverridesMatch() {
        let map = ["Work": "RAS"]
        #expect(UsageTrackerSync.resolve(swivelProfile: "Work", trackerProfiles: profiles, nameMap: map)?.id == "7D8E4458")
    }

    @Test func recordRoundTrip() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swivel-usage-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(UsageTrackerSync.loadRecord(home: home) == nil)

        let url = UsageTrackerSync.recordURL(home: home)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"at":"2026-09-21T13:57:00Z","kind":"switched","profile":"RAS"}"#.utf8).write(to: url)

        let record = try #require(UsageTrackerSync.loadRecord(home: home))
        #expect(record.outcome == .switched("RAS"))
    }
}

import AppKit
import Foundation
import os.log

enum UsageTrackerSync {
    static let bundleID = "HamedElfayome.Claude-Usage"
    static let profilesKey = "profiles_v3"
    static let activeKey = "activeProfileId"

    struct TrackerProfile: Equatable {
        let id: String
        let name: String
    }

    enum Outcome: Equatable {
        case notInstalled
        case noMatch(String)
        case alreadyActive(String)
        case switched(String)
        case failed(String)
    }

    struct Record: Codable, Equatable {
        enum Kind: String, Codable {
            case notInstalled, noMatch, alreadyActive, switched, failed
        }

        let at: Date
        let kind: Kind
        let profile: String?
        let detail: String?

        var outcome: Outcome {
            switch kind {
            case .notInstalled: return .notInstalled
            case .noMatch: return .noMatch(profile ?? "")
            case .alreadyActive: return .alreadyActive(profile ?? "")
            case .switched: return .switched(profile ?? "")
            case .failed: return .failed(detail ?? "")
            }
        }
    }

    private static let log = Logger(subsystem: "com.swivel.app", category: "UsageTrackerSync")

    static func recordURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Swivel/usage-tracker.json")
    }

    static func nameMapURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Swivel/usage-profile-map.json")
    }

    static func loadRecord(home: URL) -> Record? {
        guard let data = try? Data(contentsOf: recordURL(home: home)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Record.self, from: data)
    }

    static func decodeProfiles(_ data: Data) -> [TrackerProfile] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { return nil }
            return TrackerProfile(id: id, name: name)
        }
    }

    static func resolve(
        swivelProfile: String,
        trackerProfiles: [TrackerProfile],
        nameMap: [String: String] = [:]
    ) -> TrackerProfile? {
        let wanted = (nameMap[swivelProfile] ?? swivelProfile).lowercased()
        return trackerProfiles.first { $0.name.lowercased() == wanted }
    }

    @discardableResult
    static func activate(swivelProfile: String, home: URL, now: () -> Date = Date.init) -> Outcome {
        let outcome = perform(swivelProfile: swivelProfile, home: home)
        save(outcome: outcome, at: now(), home: home)
        return outcome
    }

    private static func perform(swivelProfile: String, home: URL) -> Outcome {
        guard let defaults = UserDefaults(suiteName: bundleID),
              let data = defaults.data(forKey: profilesKey) else {
            log.info("usage tracker not installed or has no profiles")
            return .notInstalled
        }

        let profiles = decodeProfiles(data)
        guard let target = resolve(
            swivelProfile: swivelProfile,
            trackerProfiles: profiles,
            nameMap: loadNameMap(home: home)
        ) else {
            log.error("no usage tracker profile named \(swivelProfile, privacy: .public)")
            return .noMatch(swivelProfile)
        }

        if defaults.string(forKey: activeKey) == target.id {
            log.info("usage tracker already on \(target.name, privacy: .public)")
            return .alreadyActive(target.name)
        }

        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        if wasRunning, !quitTracker() {
            log.error("usage tracker did not quit; leaving its profile alone")
            return .failed("tracker did not quit")
        }

        defaults.set(target.id, forKey: activeKey)
        defaults.synchronize()

        if wasRunning {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return .failed("tracker app not found")
            }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
        log.info("usage tracker switched to \(target.name, privacy: .public)")
        return .switched(target.name)
    }

    private static func quitTracker() -> Bool {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func loadNameMap(home: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: nameMapURL(home: home)),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return map
    }

    private static func save(outcome: Outcome, at date: Date, home: URL) {
        let record: Record
        switch outcome {
        case .notInstalled: record = Record(at: date, kind: .notInstalled, profile: nil, detail: nil)
        case .noMatch(let name): record = Record(at: date, kind: .noMatch, profile: name, detail: nil)
        case .alreadyActive(let name): record = Record(at: date, kind: .alreadyActive, profile: name, detail: nil)
        case .switched(let name): record = Record(at: date, kind: .switched, profile: name, detail: nil)
        case .failed(let reason): record = Record(at: date, kind: .failed, profile: nil, detail: reason)
        }
        let url = recordURL(home: home)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(record).write(to: url, options: .atomic)
        } catch {
            log.error("usage tracker record write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

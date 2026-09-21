import Foundation
import os.log

enum SessionMirror {
    enum Outcome: Equatable {
        case skipped
        case succeeded
        case failed(Int32)
        case timedOut
    }

    struct Record: Codable, Equatable {
        enum Kind: String, Codable {
            case skipped, succeeded, failed, timedOut
        }

        let at: Date
        let kind: Kind
        let exitStatus: Int32?
        let summary: String?

        var outcome: Outcome {
            switch kind {
            case .skipped: return .skipped
            case .succeeded: return .succeeded
            case .failed: return .failed(exitStatus ?? -1)
            case .timedOut: return .timedOut
            }
        }

        var changes: [String] {
            guard let summary = summary else { return [] }
            let body = summary.components(separatedBy: ": ").last ?? summary
            return body
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { part in
                    guard let count = part.split(separator: " ").last.flatMap({ Int($0) }) else { return false }
                    return count > 0
                }
        }
    }

    static let defaultPython = URL(fileURLWithPath: "/usr/bin/python3")
    static let defaultTimeout: TimeInterval = 30

    private static let log = Logger(subsystem: "com.swivel.app", category: "SessionMirror")

    private final class OutputBox {
        var data = Data()
    }

    static func scriptURL(home: URL) -> URL {
        home.appendingPathComponent("bin/cc-mirror-sessions")
    }

    static func recordURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Swivel/session-mirror.json")
    }

    static func loadRecord(home: URL) -> Record? {
        guard let data = try? Data(contentsOf: recordURL(home: home)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Record.self, from: data)
    }

    @discardableResult
    static func run(
        home: URL,
        python: URL = defaultPython,
        timeout: TimeInterval = defaultTimeout,
        now: () -> Date = Date.init
    ) -> Outcome {
        let (outcome, summary) = execute(home: home, python: python, timeout: timeout)
        save(outcome: outcome, summary: summary, at: now(), home: home)
        return outcome
    }

    private static func execute(home: URL, python: URL, timeout: TimeInterval) -> (Outcome, String?) {
        let fm = FileManager.default
        let script = scriptURL(home: home)
        guard fm.fileExists(atPath: script.path), fm.isExecutableFile(atPath: python.path) else {
            log.info("session mirror skipped: \(script.path, privacy: .public) or \(python.path, privacy: .public) missing")
            return (.skipped, nil)
        }

        let proc = Process()
        proc.executableURL = python
        proc.arguments = [script.path, "--quiet"]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        let outPipe = Pipe()
        proc.standardOutput = outPipe

        let finished = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in finished.signal() }
        do {
            try proc.run()
        } catch {
            log.error("session mirror failed to launch: \(error.localizedDescription, privacy: .public)")
            return (.failed(-1), nil)
        }

        let output = OutputBox()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            log.error("session mirror timed out after \(timeout, privacy: .public)s")
            return (.timedOut, nil)
        }
        _ = drained.wait(timeout: .now() + 2)
        let text = String(data: output.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = (text?.isEmpty ?? true) ? nil : text

        let status = proc.terminationStatus
        guard status == 0 else {
            log.error("session mirror exited with status \(status, privacy: .public)")
            return (.failed(status), summary)
        }
        log.info("session mirror finished: \(summary ?? "no changes", privacy: .public)")
        return (.succeeded, summary)
    }

    private static func save(outcome: Outcome, summary: String?, at date: Date, home: URL) {
        let record: Record
        switch outcome {
        case .skipped: record = Record(at: date, kind: .skipped, exitStatus: nil, summary: nil)
        case .succeeded: record = Record(at: date, kind: .succeeded, exitStatus: 0, summary: summary)
        case .failed(let status): record = Record(at: date, kind: .failed, exitStatus: status, summary: summary)
        case .timedOut: record = Record(at: date, kind: .timedOut, exitStatus: nil, summary: nil)
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
            log.error("session mirror record write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

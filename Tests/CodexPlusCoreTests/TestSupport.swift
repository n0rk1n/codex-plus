import Foundation
import CoreGraphics
import CodexPlusCore

private let testRunRecorder = TestRunRecorder()

var failures: [String] {
    get {
        testRunRecorder.failures
    }
    set {
        testRunRecorder.setFailures(newValue)
    }
}

var assertionCount: Int {
    get {
        testRunRecorder.assertionCount
    }
    set {
        testRunRecorder.setAssertionCount(newValue)
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    testRunRecorder.record(condition(), message: message)
}

private final class TestRunRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var failureStorage: [String] = []
    private var assertionCountStorage = 0

    var failures: [String] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return failureStorage
    }

    var assertionCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }

        return assertionCountStorage
    }

    func setFailures(_ failures: [String]) {
        lock.lock()
        defer {
            lock.unlock()
        }

        failureStorage = failures
    }

    func setAssertionCount(_ assertionCount: Int) {
        lock.lock()
        defer {
            lock.unlock()
        }

        assertionCountStorage = assertionCount
    }

    func record(_ passed: Bool, message: String) {
        lock.lock()
        defer {
            lock.unlock()
        }

        assertionCountStorage += 1

        if !passed {
            failureStorage.append(message)
        }
    }
}

final class LockedRunCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedEvents: [CodexEvent] = []
    private var capturedResults: [CodexRunResult] = []

    func appendEvent(_ event: CodexEvent) {
        lock.lock()
        defer {
            lock.unlock()
        }

        capturedEvents.append(event)
    }

    func appendResult(_ result: CodexRunResult) {
        lock.lock()
        defer {
            lock.unlock()
        }

        capturedResults.append(result)
    }

    func events() -> [CodexEvent] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedEvents
    }

    func results() -> [CodexRunResult] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedResults
    }
}

final class SequenceBatteryProvider: BatteryStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [BatteryStatus]

    init(_ statuses: [BatteryStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> BatteryStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}

final class SequenceCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CodexUsageStatus]

    init(_ statuses: [CodexUsageStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> CodexUsageStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}

final class SequenceDailyTokenProvider: DailyTokenUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [DailyTokenStatus]

    init(_ statuses: [DailyTokenStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> DailyTokenStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}

final class MemoryCodexUsageStatusCache: CodexUsageStatusCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: CodexUsageStatus?
    private var savedStatusValue: CodexUsageStatus?
    private var loadStatusCount = 0

    init(_ storedStatus: CodexUsageStatus? = nil) {
        self.storedStatus = storedStatus
    }

    func loadStatus() -> CodexUsageStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        loadStatusCount += 1
        return storedStatus
    }

    func saveStatus(_ status: CodexUsageStatus) {
        lock.lock()
        defer {
            lock.unlock()
        }

        savedStatusValue = status
        storedStatus = status
    }

    var savedStatus: CodexUsageStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return savedStatusValue
    }

    var loadCount: Int {
        lock.lock()
        defer {
            lock.unlock()
        }

        return loadStatusCount
    }
}

final class MemoryDailyTokenStatusCache: DailyTokenStatusCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: DailyTokenStatus?
    private var savedStatusValue: DailyTokenStatus?

    init(_ storedStatus: DailyTokenStatus? = nil) {
        self.storedStatus = storedStatus
    }

    func loadStatus() -> DailyTokenStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storedStatus
    }

    func saveStatus(_ status: DailyTokenStatus) {
        lock.lock()
        defer {
            lock.unlock()
        }

        savedStatusValue = status
        storedStatus = status
    }

    var savedStatus: DailyTokenStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return savedStatusValue
    }
}

final class BlockingCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let status: CodexUsageStatus
    private var callWasOnMainThreadValue: Bool?

    init(status: CodexUsageStatus) {
        self.status = status
    }

    func currentStatus() -> CodexUsageStatus {
        lock.lock()
        callWasOnMainThreadValue = Thread.isMainThread
        lock.unlock()

        started.signal()
        _ = releaseSemaphore.wait(timeout: .now() + .seconds(2))
        finished.signal()

        return status
    }

    func release() {
        releaseSemaphore.signal()
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + .seconds(2)) == .success
    }

    func waitUntilFinished() -> Bool {
        finished.wait(timeout: .now() + .seconds(2)) == .success
    }

    var callWasOnMainThread: Bool? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return callWasOnMainThreadValue
    }
}

final class BlockingDailyTokenProvider: DailyTokenUsageProviding, @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let status: DailyTokenStatus

    init(status: DailyTokenStatus) {
        self.status = status
    }

    func currentStatus() -> DailyTokenStatus {
        started.signal()
        _ = releaseSemaphore.wait(timeout: .now() + .seconds(2))
        finished.signal()

        return status
    }

    func release() {
        releaseSemaphore.signal()
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + .seconds(2)) == .success
    }

    func waitUntilFinished() -> Bool {
        finished.wait(timeout: .now() + .seconds(2)) == .success
    }
}

func makeTemporaryScript(named name: String, contents: String) -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "codex-plus-\(UUID().uuidString)-\(name).sh"
    )

    do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        expect(false, "temporary script \(name) can be written")
    }

    return url.path
}

func makeTemporaryDirectory(named name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "codex-plus-\(UUID().uuidString)-\(name)",
        isDirectory: true
    )

    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        expect(false, "temporary directory \(name) can be created")
    }

    return url
}

func writeText(_ text: String, to url: URL) {
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        expect(false, "temporary text file \(url.lastPathComponent) can be written")
    }
}

func setModificationDate(_ date: Date, for url: URL) {
    do {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    } catch {
        expect(false, "temporary file \(url.lastPathComponent) modification date can be set")
    }
}

func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return true
        }

        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    return condition()
}

func agentMessageTexts(from events: [CodexEvent]) -> [String] {
    events.compactMap { event in
        if case let .agentMessage(text) = event {
            return text
        }

        return nil
    }
}

func jsonObject(from line: String) -> [String: Any] {
    guard
        let data = line.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }

    return object
}

func jsonValue(_ object: [String: Any], _ path: String...) -> Any? {
    var current: Any? = object

    for key in path {
        current = (current as? [String: Any])?[key]
    }

    return current
}

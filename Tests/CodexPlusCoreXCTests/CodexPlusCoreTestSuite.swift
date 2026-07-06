import Foundation
import XCTest

final class CodexPlusCoreTestSuite: XCTestCase {
    func testLegacyRunnerSuites() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scratchPath = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-plus-legacy-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: scratchPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift",
            "run",
            "--package-path",
            packageRoot.path,
            "--scratch-path",
            scratchPath.path,
            "CodexPlusCoreLegacyTests"
        ]
        process.environment = ProcessInfo.processInfo.environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("CodexPlusCoreTests passed:"), output)
    }
}

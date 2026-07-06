import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
    func testCoreSourcesDoNotImportAppFrameworks() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let coreURL = root.appendingPathComponent("Sources/CodexPlusCore", isDirectory: true)
        let files = try swiftFiles(under: coreURL)

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("import SwiftUI"), "\(file.path) must not import SwiftUI")
            XCTAssertFalse(text.contains("import AppKit"), "\(file.path) must not import AppKit")
        }
    }

    func testWindowCoordinatorDoesNotReferenceLegacyConversationRuntime() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let file = root.appendingPathComponent("Sources/CodexPlusApp/WindowCoordinator.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(text.contains("ConversationCoordinator"))
        XCTAssertFalse(text.contains("CodexRunController"))
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        guard let enumerator else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }
}

import Foundation
import XCTest
@testable import CodexPlusCore

final class ContextCompressionModelTests: XCTestCase {
    func testVersionOperationRawValuesMatchPersistenceContract() {
        XCTAssertEqual(CompressionVersionOperation.original.rawValue, "original")
        XCTAssertEqual(CompressionVersionOperation.manualEdit.rawValue, "manual_edit")
        XCTAssertEqual(CompressionVersionOperation.defaultCompression.rawValue, "default_compression")
        XCTAssertEqual(CompressionVersionOperation.customCompression.rawValue, "custom_compression")
        XCTAssertEqual(CompressionVersionOperation.systemCompression.rawValue, "system_compression")
        XCTAssertEqual(CompressionVersionOperation.exclude.rawValue, "exclude")
        XCTAssertEqual(CompressionVersionOperation.failedCompression.rawValue, "failed_compression")
        XCTAssertEqual(CompressionVersionOperation.tombstone.rawValue, "tombstone")
    }

    func testActiveEligibilityRejectsFailedAndTombstonedVersions() {
        let activeManualEdit = compressionVersion(operation: .manualEdit, status: .active)
        let failedAttempt = compressionVersion(operation: .failedCompression, status: .failed)
        let tombstone = compressionVersion(operation: .tombstone, status: .tombstoned)
        let historicalCompression = compressionVersion(operation: .defaultCompression, status: .historical)

        XCTAssertTrue(activeManualEdit.canBecomeActive)
        XCTAssertFalse(failedAttempt.canBecomeActive)
        XCTAssertFalse(tombstone.canBecomeActive)
        XCTAssertTrue(historicalCompression.canBecomeActive)
    }

    func testExcludedVersionsCanBeActiveButEmitNoModelInput() {
        let excluded = compressionVersion(operation: .exclude, status: .active)

        XCTAssertTrue(excluded.canBecomeActive)
        XCTAssertFalse(excluded.emitsModelInput)
    }

    func testEmptyManualEditIsValidModelInput() {
        let emptyManualEdit = compressionVersion(operation: .manualEdit, status: .active, content: "")

        XCTAssertTrue(emptyManualEdit.canBecomeActive)
        XCTAssertTrue(emptyManualEdit.emitsModelInput)
        XCTAssertEqual(emptyManualEdit.content, "")
    }

    func testOperationsThatRunProvidersRequireCompressionInputRecords() {
        XCTAssertFalse(CompressionVersionOperation.original.requiresInputRecord)
        XCTAssertFalse(CompressionVersionOperation.manualEdit.requiresInputRecord)
        XCTAssertTrue(CompressionVersionOperation.defaultCompression.requiresInputRecord)
        XCTAssertTrue(CompressionVersionOperation.customCompression.requiresInputRecord)
        XCTAssertTrue(CompressionVersionOperation.systemCompression.requiresInputRecord)
        XCTAssertFalse(CompressionVersionOperation.exclude.requiresInputRecord)
        XCTAssertTrue(CompressionVersionOperation.failedCompression.requiresInputRecord)
        XCTAssertFalse(CompressionVersionOperation.tombstone.requiresInputRecord)
    }

    func testAssembledModelInputJoinsEmittingComponentsOnly() {
        let input = AssembledModelInput(
            components: [
                .sourceRound(
                    roundID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                    text: "A"
                ),
                .excluded(
                    roundID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
                ),
                .version(
                    versionID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
                    text: "C"
                ),
                .pendingUserPrompt("D")
            ]
        )

        XCTAssertEqual(input.text, "A\n\nC\n\nD")
    }

    private func compressionVersion(
        operation: CompressionVersionOperation,
        status: CompressionVersionStatus,
        content: String = "compressed content"
    ) -> CompressionVersion {
        CompressionVersion(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            conversationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            scopeKind: .round,
            operation: operation,
            status: status,
            content: content,
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
    }
}

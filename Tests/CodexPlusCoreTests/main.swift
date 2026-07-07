import Foundation

private func runAllLegacyTests() {
    failures = []
    assertionCount = 0

    runLegacyMainProcessRunnerTests()
    runPromptTemplateLibraryTests()
    runPromptTemplatePersistenceLegacyTests()
    MainActor.assumeIsolated {
        runLegacyMainActorTests()
        runPromptTemplateSettingsStoreLegacyTests()
        runWorkbenchProjectionTests()
        runPersistenceTests()
        runExecutionEngineTests()
        runArchiveTests()
        runWorkbenchStoreTests()
        runWorkbenchLauncherFramePolicyTests()
    }

    if failures.isEmpty {
        print("CodexPlusCoreTests passed: \(assertionCount) assertions")
    } else {
        for failure in failures {
            fputs("FAIL: \(failure)\n", stderr)
        }

        exit(1)
    }
}

runAllLegacyTests()

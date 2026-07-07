import Testing
@testable import CodexPlusCore

struct MultilineInputDefaultsTests {
    @Test func compactPromptLineLimitMatchesExistingBehavior() {
        #expect(MultilineInputDefaults.compactPromptLineLimit == 1...3)
    }

    @Test func conversationPromptLineLimitMatchesExistingBehavior() {
        #expect(MultilineInputDefaults.conversationPromptLineLimit == 1...4)
    }

    @Test func promptTemplateEditorUsesExistingTextInset() {
        #expect(MultilineInputDefaults.promptTemplateEditorInsetWidth == 12)
        #expect(MultilineInputDefaults.promptTemplateEditorInsetHeight == 12)
    }
}

# Multiline Input Components Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared multiline input defaults and reusable app components, then migrate existing multiline prompt and template fields to them.

**Architecture:** Put testable multiline input defaults in `CodexPlusCore` and keep SwiftUI/AppKit rendering in `CodexPlusApp`. Compact prompt fields use a shared SwiftUI vertical `TextField` wrapper, while long prompt-template bodies use a shared `NSTextView` wrapper moved out of the settings screen.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSTextView`, Swift Testing/XCTest package tests.

---

## File Structure

- Create `Sources/CodexPlusCore/UI/MultilineInputDefaults.swift` for default line limits and editor metrics that can be tested without loading SwiftUI.
- Create `Tests/CodexPlusCoreXCTests/MultilineInputDefaultsTests.swift` for focused tests around those defaults.
- Create `Sources/CodexPlusApp/Views/AppMultilineTextField.swift` for compact multiline text fields.
- Create `Sources/CodexPlusApp/Views/AppMultilineTextEditor.swift` for long-form multiline editors.
- Modify `Sources/CodexPlusApp/Views/CompactEntryView.swift` to use `AppMultilineTextField`.
- Modify `Sources/CodexPlusApp/Legacy/Views/ConversationView.swift` to use `AppMultilineTextField`.
- Modify `Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift` to use `AppMultilineTextField`.
- Modify `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift` to use both shared components and remove the private editor wrapper.

## Task 1: Add Testable Multiline Defaults

**Files:**
- Create: `Sources/CodexPlusCore/UI/MultilineInputDefaults.swift`
- Create: `Tests/CodexPlusCoreXCTests/MultilineInputDefaultsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter MultilineInputDefaultsTests`

Expected: fail because `MultilineInputDefaults` does not exist.

- [ ] **Step 3: Add the minimal defaults**

```swift
public enum MultilineInputDefaults {
    public static let compactPromptLineLimit = 1...3
    public static let conversationPromptLineLimit = 1...4
    public static let promptTemplateNoteLineLimit = 2...4
    public static let promptTemplateEditorInsetWidth: Double = 12
    public static let promptTemplateEditorInsetHeight: Double = 12
}
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `swift test --filter MultilineInputDefaultsTests`

Expected: pass.

## Task 2: Add Shared App Components

**Files:**
- Create: `Sources/CodexPlusApp/Views/AppMultilineTextField.swift`
- Create: `Sources/CodexPlusApp/Views/AppMultilineTextEditor.swift`

- [ ] **Step 1: Add `AppMultilineTextField`**

```swift
import SwiftUI

struct AppMultilineTextField: View {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 14
    var foregroundColor: Color = .primary
    var placeholderColor: Color = .secondary
    var lineLimit: ClosedRange<Int>
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(text: $text, axis: .vertical) {
            Text(placeholder)
                .foregroundStyle(placeholderColor)
        }
        .textFieldStyle(.plain)
        .font(.system(size: fontSize))
        .foregroundStyle(foregroundColor)
        .lineLimit(lineLimit)
        .onSubmit(onSubmit)
    }
}
```

- [ ] **Step 2: Add `AppMultilineTextEditor`**

```swift
import AppKit
import CodexPlusCore
import SwiftUI

struct AppMultilineTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled

    var fontSize: CGFloat = 13
    var insetWidth: Double = MultilineInputDefaults.promptTemplateEditorInsetWidth
    var insetHeight: Double = MultilineInputDefaults.promptTemplateEditorInsetHeight

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: insetWidth, height: insetHeight)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: insetWidth, height: insetHeight)
        textView.isEditable = isEnabled
        textView.isSelectable = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}
```

## Task 3: Migrate Existing Usages

**Files:**
- Modify: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
- Modify: `Sources/CodexPlusApp/Legacy/Views/ConversationView.swift`
- Modify: `Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift`
- Modify: `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`

- [ ] **Step 1: Replace compact prompt field**

Use `AppMultilineTextField(placeholder: "Ask Codex...", text: $prompt, fontSize: 15, foregroundColor: promptForegroundColor, placeholderColor: promptPlaceholderColor, lineLimit: MultilineInputDefaults.compactPromptLineLimit, onSubmit: submitPrompt)` and keep the existing `.focused($isPromptFocused)`.

- [ ] **Step 2: Replace conversation follow-up field**

Use `AppMultilineTextField(placeholder: "Follow up...", text: $followUp, fontSize: 14, lineLimit: MultilineInputDefaults.conversationPromptLineLimit, onSubmit: submitFollowUp)` and keep the existing `.focused($isFollowUpFocused)`.

- [ ] **Step 3: Replace draft prompt field**

Use `AppMultilineTextField(placeholder: "Ask Codex...", text: $prompt, fontSize: 15, lineLimit: MultilineInputDefaults.conversationPromptLineLimit, onSubmit: submitPrompt)` and keep the existing `.focused($isPromptFocused)`.

- [ ] **Step 4: Replace prompt-template note field**

Use `AppMultilineTextField(placeholder: "说明", text: draftTextBinding(\.note), lineLimit: MultilineInputDefaults.promptTemplateNoteLineLimit)` and keep `.disabled(!store.isEditable)`.

- [ ] **Step 5: Replace prompt-template body editor**

Change the local `editor(text:minHeight:)` helper to return `AppMultilineTextEditor(text: text).frame(minHeight: minHeight)` and remove `PromptTemplateMultilineEditor`.

## Task 4: Verify

**Files:**
- Modify only files already changed in prior tasks if verification reveals compile issues.

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter MultilineInputDefaultsTests`

Expected: pass.

- [ ] **Step 2: Run package tests**

Run: `swift test`

Expected: pass, or identify unrelated failures from existing worktree changes before making additional changes.

- [ ] **Step 3: Review final diff**

Run: `git diff -- Sources/CodexPlusCore/UI/MultilineInputDefaults.swift Tests/CodexPlusCoreXCTests/MultilineInputDefaultsTests.swift Sources/CodexPlusApp/Views/AppMultilineTextField.swift Sources/CodexPlusApp/Views/AppMultilineTextEditor.swift Sources/CodexPlusApp/Views/CompactEntryView.swift Sources/CodexPlusApp/Legacy/Views/ConversationView.swift Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`

Expected: diff is limited to shared multiline defaults, shared components, and migrations.

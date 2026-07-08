# Control Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move app-owned controls behind named rules so page views cannot define their own control styling or interaction mechanics.

**Architecture:** Add a small app-layer rule system in `Sources/CodexPlusApp/Views`, then migrate existing app-owned buttons, inputs, pickers, and toggle selectors to wrappers that apply those rules. Existing page-level business actions stay in their views; style, hit area, read-only overlays, and native SwiftUI control style choices move into rule files.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSTextView`, Swift Package Manager, source guardrail tests in `CodexPlusCoreLegacyTests`.

## Global Constraints

- App-owned SwiftUI `Button`, `TextField`, multiline inputs/editors, `Picker`, and selector `Toggle` controls must use named control rules.
- Page views may pass text, icons, bindings, disabled state, help text, accessibility labels, and action closures into a control abstraction.
- Page views may not define app control style or control-specific interaction mechanics.
- Alert buttons declared inside `.alert`, AppKit `NSAlert` buttons, `Menu` menu items, and system-owned picker menu rows remain outside the rule layer.
- Preserve exact copy: `系统内置提示词为只读内容。如需修改，请先创建用户自定义提示词。`
- Preserve existing visual behavior, layout, disabled states, help text, accessibility labels, line limits, focus behavior, submit behavior, and Chinese copy unless a rule explicitly replaces the old local style.
- Existing dirty changes in `PromptTemplateManagerView.swift` around read-only notices must be lifted into the shared read-only notice rule rather than reverted.

---

## File Structure

- Create `Sources/CodexPlusApp/Views/CodexControlRules.swift`: rule enums and private implementation helpers for hit areas, optional accessibility, and optional help text.
- Create `Sources/CodexPlusApp/Views/CodexButton.swift`: app-owned button wrapper and button rule modifier.
- Create `Sources/CodexPlusApp/Views/CodexTextField.swift`: app-owned single-line text field wrapper.
- Create `Sources/CodexPlusApp/Views/CodexMultilineTextField.swift`: rule-based wrapper around the existing vertical SwiftUI text field behavior.
- Create `Sources/CodexPlusApp/Views/CodexMultilineTextEditor.swift`: rule-based wrapper around the existing AppKit `NSTextView` behavior.
- Create `Sources/CodexPlusApp/Views/CodexPicker.swift`: app-owned picker wrapper.
- Create `Sources/CodexPlusApp/Views/CodexToggleSelector.swift`: app-owned toggle selector wrapper.
- Create `Sources/CodexPlusApp/Views/CodexReadOnlyNotice.swift`: shared read-only notice host and trigger handle.
- Modify `Sources/CodexPlusApp/Views/ButtonHitAreaModifier.swift`: remove it after all callers move to rule files.
- Modify app views under `Sources/CodexPlusApp` that currently call direct control styles.
- Modify `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`: add source guardrails and update prompt-template assertions.
- Modify `Tests/CodexPlusCoreTests/LegacyMainTests.swift`: update old source assertions from hit-area modifier names to rule wrapper usage.

### Task 1: Add Failing Source Guardrails

**Files:**
- Modify: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`
- Test: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`

**Interfaces:**
- Consumes: current source files under `Sources/CodexPlusApp`.
- Produces: `assertAppControlsUseRules(root:)`, `swiftSourceFiles(under:)`, and `isControlRuleImplementationFile(_:)` helpers used by this source-test file.

- [ ] **Step 1: Add source guardrail helpers**

Append these helpers to `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`, below `readSource(_:)`:

```swift
private func assertAppControlsUseRules(root: URL) {
    let appRoot = root.appendingPathComponent("Sources/CodexPlusApp")
    let files = swiftSourceFiles(under: appRoot)
    let forbiddenTokens = [
        ".buttonStyle(.plain)": "plain button styling belongs in CodexButton",
        ".textFieldStyle(": "text field styling belongs in CodexTextField",
        ".pickerStyle(": "picker styling belongs in CodexPicker",
        ".toggleStyle(": "toggle styling belongs in CodexToggleSelector",
        ".contentShape(": "control hit areas belong in rule files",
        ".glassEffect(": "control glass styling belongs in rule files or named containers",
        ".codexRectangleButtonHitArea(": "page views must not call hit-area helpers",
        ".codexCapsuleButtonHitArea(": "page views must not call hit-area helpers",
        ".codexCircularButtonHitArea(": "page views must not call hit-area helpers",
        ".codexRoundedButtonHitArea(": "page views must not call hit-area helpers",
        "readOnlyInputArea": "read-only control overlays belong in CodexReadOnlyNotice"
    ]

    for file in files where !isControlRuleImplementationFile(file) && !isSystemControlExceptionFile(file) {
        let source = readSource(file)
        for (token, message) in forbiddenTokens {
            expect(
                !source.contains(token),
                "\(file.path.replacingOccurrences(of: root.path + "/", with: "")): \(message)"
            )
        }
    }
}

private func assertControlRuleFilesExist(root: URL) {
    let viewsRoot = root.appendingPathComponent("Sources/CodexPlusApp/Views")
    let requiredFiles = [
        "CodexControlRules.swift",
        "CodexButton.swift",
        "CodexTextField.swift",
        "CodexMultilineTextField.swift",
        "CodexMultilineTextEditor.swift",
        "CodexPicker.swift",
        "CodexToggleSelector.swift",
        "CodexReadOnlyNotice.swift"
    ]

    for filename in requiredFiles {
        let path = viewsRoot.appendingPathComponent(filename).path
        expect(FileManager.default.fileExists(atPath: path), "\(filename) exists")
    }
}

private func assertInitialRuleNamesExist(root: URL) {
    let rules = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexControlRules.swift")
    )
    let requiredRuleNames = [
        "case toolbarCapsule",
        "case toolbarIconCircle",
        "case composerIconCircle",
        "case workspaceCapsule",
        "case workspaceClear",
        "case rowRectangle",
        "case rowRounded(cornerRadius: CGFloat)",
        "case cardRounded(cornerRadius: CGFloat)",
        "case formHeaderCapsule",
        "case formFooterCapsule",
        "case inlineTextLink",
        "case composerInline",
        "case searchField",
        "case formField",
        "case multilinePrompt",
        "case multilineNote",
        "case longPromptEditor",
        "case segmentedFilter",
        "case requiredMenu",
        "case filterToggle"
    ]

    for ruleName in requiredRuleNames {
        expect(rules.contains(ruleName), "control rules define \(ruleName)")
    }
}

private func swiftSourceFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        expect(false, "can enumerate \(root.path)")
        return []
    }

    return enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension == "swift" else {
            return nil
        }
        return url
    }
}

private func isControlRuleImplementationFile(_ url: URL) -> Bool {
    [
        "CodexControlRules.swift",
        "CodexButton.swift",
        "CodexTextField.swift",
        "CodexMultilineTextField.swift",
        "CodexMultilineTextEditor.swift",
        "CodexPicker.swift",
        "CodexToggleSelector.swift",
        "CodexReadOnlyNotice.swift"
    ].contains(url.lastPathComponent)
}

private func isSystemControlExceptionFile(_ url: URL) -> Bool {
    [
        "LiquidGlassContainer.swift",
        "PermissionPrompter.swift",
        "SettingsPanelController.swift"
    ].contains(url.lastPathComponent)
}
```

- [ ] **Step 2: Call the guardrails from the test body**

In `runPromptTemplateManagerAppSourceTests()`, after the existing `let root = ...` line, insert:

```swift
    assertControlRuleFilesExist(root: root)
    assertInitialRuleNamesExist(root: root)
    assertAppControlsUseRules(root: root)
```

- [ ] **Step 3: Run the legacy tests to verify RED**

Run:

```bash
swift run CodexPlusCoreLegacyTests
```

Expected: FAIL. The failure list must mention missing rule files and direct local control styles such as `.buttonStyle(.plain)` or `.textFieldStyle(`.

- [ ] **Step 4: Commit the failing guardrail test**

```bash
git add Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift
git commit -m "test: guard control rules"
```

### Task 2: Add Control Rule Primitives

**Files:**
- Create: `Sources/CodexPlusApp/Views/CodexControlRules.swift`
- Create: `Sources/CodexPlusApp/Views/CodexButton.swift`
- Create: `Sources/CodexPlusApp/Views/CodexTextField.swift`
- Create: `Sources/CodexPlusApp/Views/CodexMultilineTextField.swift`
- Create: `Sources/CodexPlusApp/Views/CodexMultilineTextEditor.swift`
- Create: `Sources/CodexPlusApp/Views/CodexPicker.swift`
- Create: `Sources/CodexPlusApp/Views/CodexToggleSelector.swift`
- Create: `Sources/CodexPlusApp/Views/CodexReadOnlyNotice.swift`
- Test: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`

**Interfaces:**
- Consumes: `MultilineInputDefaults` from `CodexPlusCore`.
- Produces:
  - `enum CodexButtonRule`
  - `enum CodexTextFieldRule`
  - `enum CodexMultilineTextRule`
  - `enum CodexPickerRule`
  - `enum CodexToggleSelectorRule`
  - `enum CodexReadOnlyNoticeRule`
  - `struct CodexReadOnlyNoticeHandle`
  - `struct CodexReadOnlyNoticeHost<Content: View>`
  - `struct CodexButton<Label: View>`
  - `struct CodexTextField`
  - `struct CodexMultilineTextField`
  - `struct CodexMultilineTextEditor`
  - `struct CodexPicker<SelectionValue: Hashable, Content: View>`
  - `struct CodexToggleSelector<Label: View>`

- [ ] **Step 1: Create `CodexControlRules.swift`**

```swift
import SwiftUI

enum CodexButtonRule {
    case toolbarCapsule
    case toolbarIconCircle
    case composerIconCircle
    case workspaceCapsule
    case workspaceClear
    case rowRectangle
    case rowRounded(cornerRadius: CGFloat)
    case cardRounded(cornerRadius: CGFloat)
    case formHeaderCapsule
    case formFooterCapsule
    case inlineTextLink
}

enum CodexTextFieldRule {
    case composerInline
    case searchField
    case formField
}

enum CodexMultilineTextRule {
    case multilinePrompt
    case multilineNote
    case longPromptEditor
}

enum CodexPickerRule {
    case segmentedFilter
    case requiredMenu
}

enum CodexToggleSelectorRule {
    case filterToggle
}

enum CodexReadOnlyNoticeRule {
    case promptTemplateSystemTemplate

    var message: String {
        switch self {
        case .promptTemplateSystemTemplate:
            return "系统内置提示词为只读内容。如需修改，请先创建用户自定义提示词。"
        }
    }
}

enum CodexControlHitShape {
    case rectangle
    case capsule
    case circle
    case rounded(cornerRadius: CGFloat)
}

extension View {
    @ViewBuilder
    func codexControlHitArea(_ shape: CodexControlHitShape) -> some View {
        switch shape {
        case .rectangle:
            contentShape(Rectangle())
        case .capsule:
            contentShape(Capsule(style: .continuous))
        case .circle:
            contentShape(Circle())
        case let .rounded(cornerRadius):
            contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func codexOptionalHelp(_ help: String?) -> some View {
        if let help {
            self.help(help)
        } else {
            self
        }
    }

    @ViewBuilder
    func codexOptionalAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }
    }

    @ViewBuilder
    func codexReadOnlyControlOverlay(_ handle: CodexReadOnlyNoticeHandle?) -> some View {
        overlay {
            if let handle, handle.isReadOnly {
                Color.clear
                    .codexControlHitArea(.rectangle)
                    .onTapGesture(perform: handle.show)
            }
        }
    }
}
```

- [ ] **Step 2: Create `CodexReadOnlyNotice.swift`**

```swift
import SwiftUI

struct CodexReadOnlyNoticeHandle {
    let isReadOnly: Bool
    let show: () -> Void
}

struct CodexReadOnlyNoticeHost<Content: View>: View {
    let isReadOnly: Bool
    let rule: CodexReadOnlyNoticeRule
    @ViewBuilder let content: (CodexReadOnlyNoticeHandle) -> Content

    @State private var isShowingNotice = false

    var body: some View {
        ZStack {
            content(
                CodexReadOnlyNoticeHandle(
                    isReadOnly: isReadOnly,
                    show: showNotice
                )
            )

            if isShowingNotice {
                CodexReadOnlyNoticeView(rule: rule)
            }
        }
        .onChange(of: isReadOnly) {
            if !isReadOnly {
                isShowingNotice = false
            }
        }
    }

    private func showNotice() {
        guard isReadOnly else {
            return
        }
        guard !isShowingNotice else {
            return
        }

        withAnimation(.easeOut(duration: 0.16)) {
            isShowingNotice = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeIn(duration: 0.2)) {
                isShowingNotice = false
            }
        }
    }
}

private struct CodexReadOnlyNoticeView: View {
    let rule: CodexReadOnlyNoticeRule

    var body: some View {
        Text(rule.message)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
```

- [ ] **Step 3: Create `CodexButton.swift`**

```swift
import SwiftUI

struct CodexButton<Label: View>: View {
    let rule: CodexButtonRule
    var role: ButtonRole?
    var help: String?
    var accessibilityLabel: String?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(role: role, action: action) {
            label()
        }
        .modifier(CodexButtonRuleModifier(rule: rule))
        .codexOptionalHelp(help)
        .codexOptionalAccessibilityLabel(accessibilityLabel)
    }
}

private struct CodexButtonRuleModifier: ViewModifier {
    let rule: CodexButtonRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .toolbarCapsule:
            content
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .compositingGroup()
                .mask(Capsule(style: .continuous))
                .codexControlHitArea(.capsule)
        case .toolbarIconCircle:
            content
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Circle())
                .compositingGroup()
                .mask(Circle())
                .codexControlHitArea(.circle)
        case .composerIconCircle:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.circle)
        case .workspaceCapsule:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.capsule)
        case .workspaceClear:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rectangle)
        case .rowRectangle:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rectangle)
        case let .rowRounded(cornerRadius):
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rounded(cornerRadius: cornerRadius))
        case let .cardRounded(cornerRadius):
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rounded(cornerRadius: cornerRadius))
        case .formHeaderCapsule:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.capsule)
        case .formFooterCapsule:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.capsule)
        case .inlineTextLink:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rectangle)
        }
    }
}
```

- [ ] **Step 4: Create input and selector wrappers**

Create `Sources/CodexPlusApp/Views/CodexTextField.swift`:

```swift
import SwiftUI

struct CodexTextField: View {
    let rule: CodexTextFieldRule
    let placeholder: String
    @Binding var text: String
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .modifier(CodexTextFieldRuleModifier(rule: rule))
            .onSubmit(onSubmit)
            .codexReadOnlyControlOverlay(readOnlyNotice)
    }
}

private struct CodexTextFieldRuleModifier: ViewModifier {
    let rule: CodexTextFieldRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .composerInline:
            content
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1)
                .submitLabel(.send)
        case .searchField:
            content
                .textFieldStyle(.roundedBorder)
        case .formField:
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}
```

Create `Sources/CodexPlusApp/Views/CodexMultilineTextField.swift`:

```swift
import CodexPlusCore
import SwiftUI

struct CodexMultilineTextField: View {
    let rule: CodexMultilineTextRule
    let placeholder: String
    @Binding var text: String
    var foregroundColor: Color = .primary
    var placeholderColor: Color = .secondary
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
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
        .codexReadOnlyControlOverlay(readOnlyNotice)
    }

    private var fontSize: CGFloat {
        switch rule {
        case .multilinePrompt:
            return 15
        case .multilineNote:
            return 14
        case .longPromptEditor:
            return 13
        }
    }

    private var lineLimit: ClosedRange<Int> {
        switch rule {
        case .multilinePrompt:
            return MultilineInputDefaults.conversationPromptLineLimit
        case .multilineNote:
            return MultilineInputDefaults.promptTemplateNoteLineLimit
        case .longPromptEditor:
            return 1...1
        }
    }
}
```

Create `Sources/CodexPlusApp/Views/CodexMultilineTextEditor.swift`:

```swift
import AppKit
import CodexPlusCore
import SwiftUI

struct CodexMultilineTextEditor: NSViewRepresentable {
    let rule: CodexMultilineTextRule
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

Create `Sources/CodexPlusApp/Views/CodexPicker.swift`:

```swift
import SwiftUI

struct CodexPicker<SelectionValue: Hashable, Content: View>: View {
    let rule: CodexPickerRule
    let title: String
    @Binding var selection: SelectionValue
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Picker(title, selection: $selection) {
            content()
        }
        .modifier(CodexPickerRuleModifier(rule: rule))
        .codexReadOnlyControlOverlay(readOnlyNotice)
    }
}

private struct CodexPickerRuleModifier: ViewModifier {
    let rule: CodexPickerRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .segmentedFilter:
            content
                .pickerStyle(.segmented)
                .labelsHidden()
        case .requiredMenu:
            content
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

Create `Sources/CodexPlusApp/Views/CodexToggleSelector.swift`:

```swift
import SwiftUI

struct CodexToggleSelector<Label: View>: View {
    let rule: CodexToggleSelectorRule
    @Binding var isOn: Bool
    var help: String?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .modifier(CodexToggleSelectorRuleModifier(rule: rule))
        .codexOptionalHelp(help)
    }
}

private struct CodexToggleSelectorRuleModifier: ViewModifier {
    let rule: CodexToggleSelectorRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .filterToggle:
            content
                .toggleStyle(.button)
        }
    }
}
```

- [ ] **Step 5: Run the legacy tests to verify partial GREEN**

Run:

```bash
swift run CodexPlusCoreLegacyTests
```

Expected: FAIL remains because app views still contain direct page-owned control style. The failure list must no longer mention missing rule files or missing rule names.

- [ ] **Step 6: Commit the rule primitives**

```bash
git add Sources/CodexPlusApp/Views/CodexControlRules.swift Sources/CodexPlusApp/Views/CodexButton.swift Sources/CodexPlusApp/Views/CodexTextField.swift Sources/CodexPlusApp/Views/CodexMultilineTextField.swift Sources/CodexPlusApp/Views/CodexMultilineTextEditor.swift Sources/CodexPlusApp/Views/CodexPicker.swift Sources/CodexPlusApp/Views/CodexToggleSelector.swift Sources/CodexPlusApp/Views/CodexReadOnlyNotice.swift
git commit -m "feat(app): add control rules"
```

### Task 3: Migrate Workbench and Shared App Buttons

**Files:**
- Modify: `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchLauncherView.swift`
- Modify: `Sources/CodexPlusApp/Views/ConversationTechnicalEventGroupRow.swift`
- Modify: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
- Modify: `Sources/CodexPlusApp/Views/CodexDesktopTileView.swift`
- Modify: `Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift`
- Test: `Tests/CodexPlusCoreTests/LegacyMainTests.swift`
- Test: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`

**Interfaces:**
- Consumes: `CodexButton<Label>`, `CodexButtonRule`.
- Produces: migrated workbench and shared buttons with no page-owned `.buttonStyle(.plain)` or hit-area helper calls.

- [ ] **Step 1: Replace top strip helpers**

In `TopProjectStripView.stripActionButton`, replace `Button(...).buttonStyle...` with:

```swift
    private func stripActionButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        CodexButton(rule: .toolbarCapsule, action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
```

In `TopProjectStripView.iconActionButton`, replace `Button(...).buttonStyle...` with:

```swift
        CodexButton(
            rule: .toolbarIconCircle,
            help: help,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
        }
```

In `TopProjectStripView.projectCard`, replace the outer `Button` wrapper with:

```swift
        CodexButton(
            rule: .cardRounded(cornerRadius: WorkbenchMetrics.projectCardCornerRadius),
            action: {
                if let conversationID = card.conversationID {
                    actions.selectConversation(conversationID)
                } else {
                    actions.selectProject(card.id)
                }
            }
        ) {
            LiquidGlassContainer(cornerRadius: WorkbenchMetrics.projectCardCornerRadius) {
                projectCardContent(card)
            }
        }
```

Extract the current project-card label body into:

```swift
    private func projectCardContent(_ card: WorkbenchProjectCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                projectCardLine(systemName: "folder", label: "项目：", value: card.projectName)
                projectCardLine(systemName: "text.bubble", label: "对话：", value: card.conversationTitle)

                HStack(spacing: 8) {
                    Text("\(card.visibleConversationCount) 条")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if card.overflowCount != nil, let overflowCount = card.overflowCount {
                projectCardOverflowMenu(card: card, overflowCount: overflowCount)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 280, alignment: .leading)
    }
```

Keep `Menu` content native and unwrapped because menu rows are out of scope.

- [ ] **Step 2: Replace composer buttons**

In `WorkbenchComposerView.composerButton`, use:

```swift
            CodexButton(rule: .composerIconCircle, action: actions.stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
            }
            .disabled(snapshot.activeConversation == nil)
```

and:

```swift
            CodexButton(rule: .composerIconCircle, action: submitPrompt) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
            }
            .disabled(
                !snapshot.canSubmitPrompt
                    || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
```

In `promptOptimizationButton`, use:

```swift
        CodexButton(
            rule: .composerIconCircle,
            help: isOptimizingPrompt ? "正在优化提示词" : "优化输入提示词",
            accessibilityLabel: isOptimizingPrompt ? "正在优化提示词" : "优化输入提示词",
            action: optimizePrompt
        ) {
            Image(systemName: isOptimizingPrompt ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOptimizingPrompt ? .yellow : .secondary)
                .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
                .scaleEffect(isOptimizingPrompt && bulbPulse ? 1.12 : 1.0)
                .opacity(isOptimizingPrompt && bulbPulse ? 0.72 : 1.0)
                .animation(
                    isOptimizingPrompt
                        ? .easeInOut(duration: 0.72).repeatForever(autoreverses: true)
                        : .default,
                    value: bulbPulse
                )
        }
        .disabled(isOptimizingPrompt || snapshot.composerAction != .send)
```

In `workspacePickerButton`, replace the picker `Button` with `CodexButton(rule: .workspaceCapsule, action: actions.pickWorkspace) { ... }`. Keep the existing outer glass capsule on the `HStack` because it frames both picker and clear controls as one composite control.

In `workspaceClearButton`, replace the `Button` with:

```swift
        CodexButton(
            rule: .workspaceClear,
            help: WorkbenchStrings.clearWorkspace,
            accessibilityLabel: WorkbenchStrings.clearWorkspace,
            action: actions.clearWorkspace
        ) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: WorkbenchMetrics.composerControlHeight)
        }
        .padding(.trailing, 6)
```

- [ ] **Step 3: Replace archive and row buttons**

In `WorkbenchConversationView.archiveButton`, wrap the label with:

```swift
        CodexButton(rule: .toolbarCapsule, help: "归档当前对话", action: {
            actions.archiveConversation(conversationID)
        }) {
            Label("归档", systemImage: "archivebox.and.arrow.down")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
```

In `ArchivedConversationView`, replace result-row open buttons with `CodexButton(rule: .rowRectangle, action: { actions.open(record.id) }) { ... }`. Keep `.swipeActions(edge: .trailing)` attached to the `CodexButton` result.

In `restoreNoticeView`, replace the inline jump `Button` with:

```swift
            CodexButton(rule: .inlineTextLink, action: {
                actions.jumpToRestored(notice.conversationID)
                restoreNotice = nil
            }) {
                Text("跳转对话")
                    .foregroundStyle(Color.blue.opacity(0.72))
            }
```

In `ConversationTechnicalEventGroupRow`, replace the toggle `Button` with `CodexButton(rule: .rowRectangle, action: onToggle) { ... }`.

- [ ] **Step 4: Replace shared app buttons**

In `CompactEntryView`, replace the workspace button with `CodexButton(rule: .rowRectangle, help: "Choose Workspace", accessibilityLabel: "Choose Workspace", action: { onOpenDraft(prompt) }) { ... }`.

In `CodexDesktopTileView`, replace the tile `Button` with `CodexButton(rule: .cardRounded(cornerRadius: 22), action: onOpen) { ... }`.

In `SideEdgeAffordanceView`, replace the button with `CodexButton(rule: .toolbarCapsule, action: onActivate) { ... }`. Keep the existing label content inside the wrapper.

In `WorkbenchView`, replace the error-clear `Button` with `CodexButton(rule: .toolbarIconCircle, action: { store.clearError() }) { ... }`.

In `WorkbenchLauncherView`, move its circular launcher button through `CodexButton(rule: .toolbarIconCircle, action: onActivate) { ... }` and keep launcher-specific frame positioning outside the button.

- [ ] **Step 5: Update source assertions that looked for old hit-area modifiers**

In `LegacyMainTests`, replace assertions for `.codexRectangleButtonHitArea()` and `.codexRoundedButtonHitArea(...)` with rule wrapper assertions:

```swift
expect(
    rowButtonSource.contains("CodexButton(rule: .rowRectangle"),
    "archived conversation result rows use the shared row rule"
)
```

and:

```swift
expect(
    projectCardButtonSource.contains(
        "CodexButton(\n            rule: .cardRounded(cornerRadius: WorkbenchMetrics.projectCardCornerRadius)"
    ),
    "top project cards use the shared rounded card rule"
)
```

In `PromptTemplateManagerAppSourceTests`, replace:

```swift
topProjectStripView.contains(".codexCircularButtonHitArea()")
```

with:

```swift
topProjectStripView.contains("rule: .toolbarIconCircle")
```

- [ ] **Step 6: Run the legacy tests**

Run:

```bash
swift run CodexPlusCoreLegacyTests
```

Expected: FAIL remains if prompt-template, legacy, or input controls are not migrated yet. Workbench/shared button failures from this task should be gone.

- [ ] **Step 7: Commit migrated workbench buttons**

```bash
git add Sources/CodexPlusApp/Workbench/TopProjectStripView.swift Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift Sources/CodexPlusApp/Workbench/WorkbenchView.swift Sources/CodexPlusApp/Workbench/WorkbenchLauncherView.swift Sources/CodexPlusApp/Views/ConversationTechnicalEventGroupRow.swift Sources/CodexPlusApp/Views/CompactEntryView.swift Sources/CodexPlusApp/Views/CodexDesktopTileView.swift Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift Tests/CodexPlusCoreTests/LegacyMainTests.swift Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift
git commit -m "refactor(app): route workbench buttons through rules"
```

### Task 4: Migrate Prompt Template Manager Controls

**Files:**
- Modify: `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
- Modify: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`
- Test: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`

**Interfaces:**
- Consumes: `CodexButton`, `CodexTextField`, `CodexMultilineTextField`, `CodexMultilineTextEditor`, `CodexPicker`, `CodexToggleSelector`, `CodexReadOnlyNoticeHost`.
- Produces: prompt-template manager with no page-local `readOnlyInputArea`, direct `.textFieldStyle`, `.pickerStyle`, `.toggleStyle`, `.buttonStyle`, or hit-area helpers.

- [ ] **Step 1: Replace the detail pane read-only notice state**

Remove the local `@State private var isShowingReadOnlyTemplateNotice = false`, `readOnlyTemplateNotice`, `readOnlyInputArea`, and `showReadOnlyTemplateNotice()` from `PromptTemplateManagerView.swift`.

Wrap the existing detail-pane `ZStack` content with:

```swift
                CodexReadOnlyNoticeHost(
                    isReadOnly: !store.isEditable,
                    rule: .promptTemplateSystemTemplate
                ) { readOnlyNotice in
                    VStack(spacing: 0) {
                        detailHeader

                        Divider()
                            .overlay(.white.opacity(0.08))

                        detailForm(readOnlyNotice: readOnlyNotice)

                        Spacer(minLength: 0)

                        Divider()
                            .overlay(.white.opacity(0.08))

                        detailFooter
                    }
                }
```

Change `private var detailForm: some View` to:

```swift
    private func detailForm(readOnlyNotice: CodexReadOnlyNoticeHandle) -> some View {
```

- [ ] **Step 2: Replace prompt-template sidebar controls**

Replace the create button with:

```swift
                    CodexButton(
                        rule: .toolbarIconCircle,
                        help: "新增用户自定义提示词",
                        action: { performOrConfirm(.create) }
                    ) {
                        sidebarIcon("plus")
                    }
```

Replace the sidebar search text field with:

```swift
                CodexTextField(
                    rule: .searchField,
                    placeholder: "搜索名称、说明、系统提示词、用户提示词",
                    text: $store.searchQuery
                )
```

Replace `sourceFilter` with:

```swift
    private var sourceFilter: some View {
        CodexPicker(rule: .segmentedFilter, title: "", selection: sourceFilterBinding) {
            Text("全部").tag(PromptTemplateSourceFilter.all)
            Text("系统内置").tag(PromptTemplateSourceFilter.source(.systemBuiltIn))
            Text("用户自定义").tag(PromptTemplateSourceFilter.source(.userCustom))
        }
    }
```

Replace filter toggles with:

```swift
                    CodexToggleSelector(
                        rule: .filterToggle,
                        isOn: typeFilterBinding(type),
                        help: type.displayName
                    ) {
                        Text(type.shortDisplayName)
                            .font(.caption.weight(.semibold))
                    }
```

- [ ] **Step 3: Replace prompt-template row and header/footer buttons**

Replace `templateRow(_:)` outer `Button` with:

```swift
        CodexButton(rule: .rowRounded(cornerRadius: 8), help: template.name, action: {
            performOrConfirm(.select(template.id))
        }) {
            VStack(alignment: .leading, spacing: 6) {
                templateRowContent(template)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(rowBackground(isSelected: store.selectedTemplateID == template.id))
        }
```

Replace detail header buttons with `CodexButton(rule: .formHeaderCapsule, ...)`. The copy button becomes:

```swift
            CodexButton(
                rule: .formHeaderCapsule,
                help: "复制当前模板为用户自定义模板",
                action: { performOrConfirm(.copy) }
            ) {
                headerActionLabel(
                    systemImage: "doc.on.doc",
                    title: store.isEditable ? "复制" : "复制为用户模板",
                    foregroundColor: .blue
                )
            }
```

Replace set-default and delete header actions the same way using `.formHeaderCapsule`.

Replace footer discard and save actions with `CodexButton(rule: .formFooterCapsule, ...)`.

Remove `.codexCapsuleButtonHitArea()` from `headerActionLabel` and `footerActionLabel`; those labels keep font, padding, foreground color, and glass only if the rule does not provide that visual. If keeping `.glassEffect` inside labels would violate guardrails, move the glass effect into `.formHeaderCapsule` and `.formFooterCapsule` rule implementations.

- [ ] **Step 4: Replace prompt-template form inputs**

Inside `detailForm(readOnlyNotice:)`, replace the name field with:

```swift
                    CodexTextField(
                        rule: .formField,
                        placeholder: "模板名称",
                        text: draftTextBinding(\.name),
                        readOnlyNotice: readOnlyNotice
                    )
                    .disabled(!store.isEditable)
```

Replace the type picker with:

```swift
                    CodexPicker(
                        rule: .requiredMenu,
                        title: "",
                        selection: draftTypeBinding,
                        readOnlyNotice: readOnlyNotice
                    ) {
                        Text("请选择类型")
                            .tag(Optional<PromptTemplateType>.none)

                        ForEach(PromptTemplateType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(Optional(type))
                        }
                    }
                    .disabled(!store.isEditable)
```

Replace system and user prompt editors with:

```swift
                    editor(text: draftTextBinding(\.systemPrompt), minHeight: 140, readOnlyNotice: readOnlyNotice)
                        .disabled(!store.isEditable)
```

and:

```swift
                    editor(text: draftTextBinding(\.userPrompt), minHeight: 100, readOnlyNotice: readOnlyNotice)
                        .disabled(!store.isEditable)
```

Replace the note field with:

```swift
                    CodexMultilineTextField(
                        rule: .multilineNote,
                        placeholder: "说明",
                        text: draftTextBinding(\.note),
                        readOnlyNotice: readOnlyNotice
                    )
                    .disabled(!store.isEditable)
```

Change the editor helper to:

```swift
    private func editor(
        text: Binding<String>,
        minHeight: CGFloat,
        readOnlyNotice: CodexReadOnlyNoticeHandle
    ) -> some View {
        CodexMultilineTextEditor(rule: .longPromptEditor, text: text)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .codexReadOnlyControlOverlay(readOnlyNotice)
    }
```

- [ ] **Step 5: Update prompt-template tests**

Replace assertions that expect old direct controls:

```swift
managerView.contains("AppMultilineTextEditor(text:")
managerView.contains("Picker(\"\", selection: sourceFilterBinding)")
managerView.contains("Picker(\"\", selection: draftTypeBinding)")
managerView.contains(".codexCapsuleButtonHitArea()")
managerView.contains("readOnlyInputArea")
managerView.contains("showReadOnlyTemplateNotice")
managerView.contains("Color.clear")
managerView.contains(".contentShape(Rectangle())")
```

with assertions that expect rule wrappers:

```swift
expect(
    managerView.contains("CodexMultilineTextEditor(rule: .longPromptEditor") &&
        managerView.contains("CodexMultilineTextField(\n                        rule: .multilineNote") &&
        multilineTextEditor.contains("textContainerInset") &&
        !managerView.contains("\n        TextEditor(text:"),
    "prompt manager multiline prompt fields use rule-based multiline controls with explicit text container inset"
)
expect(
    managerView.contains("CodexPicker(rule: .segmentedFilter") &&
        managerView.contains("Text(template.type.displayName)") &&
        !managerView.contains("Text(\"类型  \\(template.type.displayName)\")") &&
        managerView.contains("Text(template.source.displayName)") &&
        !managerView.contains("Text(\"来源  \\(template.source.displayName)\")"),
    "prompt manager sidebar removes redundant type and source labels while keeping values visible"
)
expect(
    managerView.contains("CodexPicker(\n                        rule: .requiredMenu") &&
        !managerView.contains("Picker(\"类型\", selection: draftTypeBinding)"),
    "prompt manager type menu uses the required menu rule without a duplicate picker label"
)
expect(
    managerView.contains("CodexReadOnlyNoticeHost(") &&
        managerView.contains("rule: .promptTemplateSystemTemplate") &&
        managerView.contains("readOnlyNotice: readOnlyNotice") &&
        !managerView.contains("readOnlyInputArea") &&
        !managerView.contains("showReadOnlyTemplateNotice"),
    "prompt manager read-only detail controls use the shared read-only notice rule"
)
```

- [ ] **Step 6: Run the legacy tests**

Run:

```bash
swift run CodexPlusCoreLegacyTests
```

Expected: FAIL remains only for unmigrated legacy controls and old shared input wrappers. Prompt-template manager guardrail failures should be gone.

- [ ] **Step 7: Commit migrated prompt-template controls**

```bash
git add Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift
git commit -m "refactor(app): route prompt controls through rules"
```

### Task 5: Migrate Legacy Views and Input Wrappers

**Files:**
- Modify: `Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift`
- Modify: `Sources/CodexPlusApp/Legacy/Views/ConversationView.swift`
- Modify: `Sources/CodexPlusApp/Legacy/Views/ConversationTabHeaderView.swift`
- Modify: `Sources/CodexPlusApp/Views/AppMultilineTextField.swift`
- Modify: `Sources/CodexPlusApp/Views/AppMultilineTextEditor.swift`
- Test: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`
- Test: `Tests/CodexPlusCoreTests/LegacyMainTests.swift`

**Interfaces:**
- Consumes: all rule wrappers created in Task 2.
- Produces: legacy views using `CodexButton` and `CodexMultilineTextField`; old `AppMultiline*` names no longer appear in page views.

- [ ] **Step 1: Replace legacy draft controls**

In `ConversationDraftView`, replace the workspace button with:

```swift
            CodexButton(
                rule: .rowRounded(cornerRadius: 8),
                help: "Choose Workspace",
                accessibilityLabel: "Choose Workspace",
                action: onPickWorkspace
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))

                    Text(workspaceText)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
```

Replace `AppMultilineTextField` with:

```swift
                    CodexMultilineTextField(
                        rule: .multilinePrompt,
                        placeholder: "Ask Codex...",
                        text: $prompt,
                        onSubmit: submitPrompt
                    )
```

Replace the send button with `CodexButton(rule: .composerIconCircle, help: "Send", accessibilityLabel: "Send", action: submitPrompt) { ... }`.

- [ ] **Step 2: Replace legacy conversation controls**

In `ConversationView.footer`, replace `AppMultilineTextField` with:

```swift
                CodexMultilineTextField(
                    rule: .multilinePrompt,
                    placeholder: "Follow up...",
                    text: $followUp,
                    onSubmit: submitFollowUp
                )
```

Replace the footer send button with `CodexButton(rule: .composerIconCircle, help: "Send", accessibilityLabel: "Send Follow-Up", action: submitFollowUp) { ... }`.

In `ConversationView.iconButton`, replace the local `Button` with:

```swift
        CodexButton(
            rule: .rowRectangle,
            help: help,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
```

- [ ] **Step 3: Replace legacy tab header buttons**

In `ConversationTabHeaderView`, replace each app-owned direct `Button` that uses `.buttonStyle(.plain)` with `CodexButton(rule: .rowRectangle, ...)`. Keep drag/drop gestures outside the button wrappers when they are row-level behavior, not button styling.

For the new-draft button, use:

```swift
                CodexButton(rule: .rowRectangle, action: onNewDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
```

For conversation tab row buttons, use:

```swift
        CodexButton(rule: .rowRectangle, action: action) {
            label
        }
```

- [ ] **Step 4: Retire old multiline wrappers from page usage**

Change `AppMultilineTextField.swift` to a compatibility shim used only by `CodexMultilineTextField` during this migration:

```swift
import SwiftUI

@available(*, deprecated, message: "Use CodexMultilineTextField with a named rule.")
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

Keep `AppMultilineTextEditor.swift` unchanged until no page uses it. The rule-based `CodexMultilineTextEditor` owns the new app-facing API.

- [ ] **Step 5: Add guardrails against old wrapper usage in page views**

In `assertAppControlsUseRules(root:)`, add forbidden tokens:

```swift
        "AppMultilineTextField(": "page views must use CodexMultilineTextField",
        "AppMultilineTextEditor(": "page views must use CodexMultilineTextEditor"
```

Update `isControlRuleImplementationFile(_:)` to allow `AppMultilineTextField.swift` and `AppMultilineTextEditor.swift` only if they remain as compatibility implementations:

```swift
        "AppMultilineTextField.swift",
        "AppMultilineTextEditor.swift"
```

- [ ] **Step 6: Run the legacy tests**

Run:

```bash
swift run CodexPlusCoreLegacyTests
```

Expected: PASS if no app-owned page controls still bypass rules.

- [ ] **Step 7: Commit migrated legacy controls**

```bash
git add Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift Sources/CodexPlusApp/Legacy/Views/ConversationView.swift Sources/CodexPlusApp/Legacy/Views/ConversationTabHeaderView.swift Sources/CodexPlusApp/Views/AppMultilineTextField.swift Sources/CodexPlusApp/Views/AppMultilineTextEditor.swift Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift Tests/CodexPlusCoreTests/LegacyMainTests.swift
git commit -m "refactor(app): route legacy controls through rules"
```

### Task 6: Remove Old Hit-Area Helper and Verify

**Files:**
- Delete: `Sources/CodexPlusApp/Views/ButtonHitAreaModifier.swift`
- Modify: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`
- Modify: `Tests/CodexPlusCoreTests/LegacyMainTests.swift`

**Interfaces:**
- Consumes: all migrated call sites from Tasks 3-5.
- Produces: no direct use of old hit-area helper names outside historical docs.

- [ ] **Step 1: Delete old hit-area helper file**

Delete `Sources/CodexPlusApp/Views/ButtonHitAreaModifier.swift` after confirming no source file references:

```bash
rg -n "codex(Rectangle|Capsule|Circular|Rounded)ButtonHitArea|ButtonHitAreaModifier" Sources Tests
```

Expected before delete: no matches in `Sources` or `Tests`, except the `rg` command itself is not stored.

- [ ] **Step 2: Tighten guardrail allowlists**

Ensure `isControlRuleImplementationFile(_:)` contains only:

```swift
private func isControlRuleImplementationFile(_ url: URL) -> Bool {
    [
        "CodexControlRules.swift",
        "CodexButton.swift",
        "CodexTextField.swift",
        "CodexMultilineTextField.swift",
        "CodexMultilineTextEditor.swift",
        "CodexPicker.swift",
        "CodexToggleSelector.swift",
        "CodexReadOnlyNotice.swift",
        "AppMultilineTextField.swift",
        "AppMultilineTextEditor.swift"
    ].contains(url.lastPathComponent)
}
```

Ensure `isSystemControlExceptionFile(_:)` contains only:

```swift
private func isSystemControlExceptionFile(_ url: URL) -> Bool {
    [
        "LiquidGlassContainer.swift",
        "PermissionPrompter.swift",
        "SettingsPanelController.swift"
    ].contains(url.lastPathComponent)
}
```

- [ ] **Step 3: Run source searches**

Run:

```bash
rg -n "\\.buttonStyle\\(\\.plain\\)|\\.textFieldStyle\\(|\\.pickerStyle\\(|\\.toggleStyle\\(|\\.glassEffect\\(|\\.codex(Rectangle|Capsule|Circular|Rounded)ButtonHitArea|readOnlyInputArea|AppMultilineTextField\\(|AppMultilineTextEditor\\(" Sources/CodexPlusApp
```

Expected: matches only inside rule files, `LiquidGlassContainer.swift`, and compatibility implementation files.

Run:

```bash
rg -n "ButtonHitAreaModifier|codexRectangleButtonHitArea|codexCapsuleButtonHitArea|codexCircularButtonHitArea|codexRoundedButtonHitArea" Sources Tests
```

Expected: no matches.

- [ ] **Step 4: Run verification commands**

Run:

```bash
swift run CodexPlusCoreLegacyTests
```

Expected: PASS and output includes `CodexPlusCoreTests passed:`.

Run:

```bash
swift build
```

Expected: PASS with exit code 0.

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 5: Commit cleanup**

```bash
git add Sources/CodexPlusApp/Views/ButtonHitAreaModifier.swift Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift Tests/CodexPlusCoreTests/LegacyMainTests.swift
git commit -m "refactor(app): remove old hit area helpers"
```

## Self-Review

- Spec coverage: Tasks 1 and 6 cover source guardrails; Task 2 creates named rules and wrappers; Tasks 3-5 migrate buttons, inputs, editors, pickers, toggles, and the read-only notice; Task 6 verifies build and legacy tests.
- Placeholder scan: this plan contains no `TBD`, `TODO`, deferred implementation markers, or unnamed files.
- Type consistency: rule names match the spec and are reused consistently across all tasks.
- Scope check: alert buttons, AppKit alert buttons, menu items, and core-layer behavior remain outside the migration.

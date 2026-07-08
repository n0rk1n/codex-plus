import CodexPlusCore
import SwiftUI

struct PromptTemplateManagerView: View {
    @ObservedObject private var store: PromptTemplateSettingsStore
    @State private var isShowingDirtyConfirmation = false
    @State private var isShowingRenamePrompt = false
    @State private var pendingAction: PendingDirtyAction?
    @State private var pendingDeleteTemplate: PromptTemplate?
    @State private var pendingRenameTemplate: PromptTemplate?
    @State private var renameText = ""

    init(repository: any PromptTemplateRepository) {
        _store = ObservedObject(wrappedValue: PromptTemplateSettingsStore(repository: repository))
    }

    init(store: PromptTemplateSettingsStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        LiquidGlassScene(
            padding: WorkbenchMetrics.scenePadding,
            minWidth: 980,
            minHeight: 620
        ) {
            HStack(spacing: 16) {
                sidebar
                    .frame(width: WorkbenchMetrics.settingsSidebarWidth)

                detailPane
            }
        }
        .alert("删除提示词模板？", isPresented: deleteConfirmationBinding, presenting: pendingDeleteTemplate) { template in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteTemplate(template.id)
                pendingDeleteTemplate = nil
            }
        } message: { template in
            Text("删除后将从提示词模板列表移除“\(template.name)”。系统内置提示词不会被删除。")
        }
        .alert("重命名提示词模板", isPresented: $isShowingRenamePrompt) {
            CodexTextField(
                rule: .formField,
                placeholder: "名称",
                text: $renameText
            )
            Button("取消", role: .cancel) {
                clearRenamePrompt()
            }
            Button("保存") {
                if let template = pendingRenameTemplate {
                    store.renameTemplate(template.id, to: renameText)
                }
                clearRenamePrompt()
            }
        } message: {
            Text("输入新的模板名称。")
        }
        .alert("保存未完成的修改？", isPresented: $isShowingDirtyConfirmation) {
            Button("取消", role: .cancel) {
                pendingAction = nil
            }
            Button("放弃修改", role: .destructive) {
                performPendingActionAfterDiscard()
            }
            Button("保存") {
                performPendingActionAfterSave()
            }
        } message: {
            Text("当前提示词模板有未保存修改。继续前请选择保存、放弃或取消。")
        }
    }

    private var sidebar: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.settingsCornerRadius) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("提示词模板")
                        .font(CodexTypography.controlLabel)

                    Spacer()

                    CodexButton(
                        rule: .toolbarIconCircle,
                        action: { performOrConfirm(.create) }
                    ) {
                        sidebarIcon("plus")
                    }
                    .help("新增用户自定义提示词")
                }

                CodexTextField(
                    rule: .searchField,
                    placeholder: "搜索名称、说明、系统提示词、用户提示词",
                    text: $store.searchQuery
                )

                sourceFilter
                typeFilter

                if store.visibleTemplates.isEmpty {
                    emptyListState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.visibleTemplates) { template in
                                templateRow(template)
                            }
                        }
                    }
                }
            }
            .padding(CodexSpacing.contentInline)
        }
    }

    private var sourceFilter: some View {
        CodexPicker(rule: .segmentedFilter, title: "", selection: sourceFilterBinding) {
            Text("全部").tag(PromptTemplateSourceFilter.all)
            Text("系统内置").tag(PromptTemplateSourceFilter.source(.systemBuiltIn))
            Text("用户自定义").tag(PromptTemplateSourceFilter.source(.userCustom))
        }
    }

    private var typeFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("类型筛选")
                .font(CodexTypography.captionStrong)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(PromptTemplateType.allCases, id: \.self) { type in
                    CodexToggleSelector(rule: .filterToggle, isOn: typeFilterBinding(type)) {
                        Text(type.shortDisplayName)
                            .font(CodexTypography.captionStrong)
                    }
                    .help(type.displayName)
                }
            }
        }
    }

    private func templateRow(_ template: PromptTemplate) -> some View {
        CodexButton(
            rule: .rowRounded(cornerRadius: 8),
            accessibilityLabel: template.name,
            action: { performOrConfirm(.select(template.id)) }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(CodexTypography.menuPrimary)
                        .lineLimit(1)

                    if store.isDefaultTemplate(template) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(CodexTypography.compactBadge)
                            .foregroundStyle(CodexColors.stateRunning)
                            .help("此类型默认模板")
                    }
                }

                templateMetadataRow(template)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CodexSpacing.tightInline)
            .background(rowBackground(isSelected: store.selectedTemplateID == template.id))
        }
        .help(template.name)
        .swipeActions(edge: .trailing) {
            if template.source == .userCustom {
                Button(role: .destructive) {
                    pendingDeleteTemplate = template
                } label: {
                    Text("删除")
                }

                Button {
                    performOrConfirm(.rename(template.id))
                } label: {
                    Text("重命名")
                }
                .tint(CodexColors.stateRunning)
            }
        }
    }

    private func templateMetadataRow(_ template: PromptTemplate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(template.type.displayName)
                .font(CodexTypography.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(template.source.displayName)
                .font(CodexTypography.caption2)
                .foregroundStyle(template.source == .systemBuiltIn ? CodexColors.stateCompleted : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? CodexColors.surfaceSelection : CodexColors.surfaceSubtle)
    }

    @ViewBuilder
    private var detailPane: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.settingsCornerRadius) {
            if store.draft == nil {
                emptyDetailState
            } else {
                VStack(spacing: 0) {
                    detailHeader

                Divider()
                    .overlay(CodexColors.surfaceDivider)

                    detailForm

                    Spacer(minLength: 0)

                    Divider()
                        .overlay(CodexColors.surfaceDivider)

                    detailFooter
                }
            }
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
            Text(detailTitle)
                .font(CodexTypography.sectionHeader)

                Text(store.isEditable ? "用户自定义提示词，可编辑并保存。" : "系统内置提示词不可直接编辑，可复制为用户模板。")
                    .font(CodexTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            CodexButton(
                rule: .formHeaderCapsule,
                action: { performOrConfirm(.copy) }
            ) {
                headerActionLabel(
                    systemImage: "doc.on.doc",
                    title: store.isEditable ? "复制" : "复制为用户模板",
                    foregroundColor: CodexColors.stateRunning
                )
            }
            .help("复制当前模板为用户自定义模板")

            if let selectedTemplate = store.selectedTemplate {
                CodexButton(
                    rule: .formHeaderCapsule,
                    isDisabled: store.isDefaultTemplate(selectedTemplate),
                    action: { store.setDefaultTemplate(selectedTemplate.id) }
                ) {
                    headerActionLabel(
                        systemImage: store.isDefaultTemplate(selectedTemplate) ? "checkmark.seal.fill" : "checkmark.seal",
                        title: store.isDefaultTemplate(selectedTemplate) ? "当前默认" : "设为默认",
                        foregroundColor: CodexColors.stateRunning
                    )
                }
                .help("设为“\(selectedTemplate.type.shortDisplayName)”类型默认模板")
            }

            if store.isEditable {
                CodexButton(
                    rule: .formHeaderCapsule,
                    role: .destructive,
                    action: { pendingDeleteTemplate = store.selectedTemplate }
                ) {
                    headerActionLabel(systemImage: "trash", title: "删除", foregroundColor: CodexColors.stateFailed)
                }
                .help("删除当前用户自定义模板")
            }
        }
        .padding(CodexSpacing.compactField)
    }

    private var detailForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodexSpacing.compactInline) {
                if let errorMessage = store.errorMessage {
                    messageRow(errorMessage, color: CodexColors.stateFailed, symbol: "exclamationmark.triangle.fill")
                }

                labeledField("名称 *") {
                    readOnlyTemplateControl { handle in
                        CodexTextField(
                            rule: .formField,
                            placeholder: "模板名称",
                            text: draftTextBinding(\.name),
                            isDisabled: !store.isEditable,
                            readOnlyNotice: handle
                        )
                    }
                }

                labeledField("类型 *") {
                    readOnlyTemplateControl { handle in
                        CodexPicker(
                            rule: .requiredMenu,
                            title: "",
                            selection: draftTypeBinding,
                            isDisabled: !store.isEditable,
                            readOnlyNotice: handle
                        ) {
                            Text("请选择类型")
                                .tag(Optional<PromptTemplateType>.none)

                            ForEach(PromptTemplateType.allCases, id: \.self) { type in
                                Text(type.displayName)
                                    .tag(Optional(type))
                            }
                        }
                    }
                }

                labeledField("系统提示词 *") {
                    readOnlyTemplateControl { handle in
                        editor(text: draftTextBinding(\.systemPrompt), minHeight: 140)
                            .disabled(!store.isEditable)
                            .codexReadOnlyControlOverlay(handle)
                    }
                }

                labeledField("用户提示词") {
                    readOnlyTemplateControl { handle in
                        editor(text: draftTextBinding(\.userPrompt), minHeight: 100)
                            .disabled(!store.isEditable)
                            .codexReadOnlyControlOverlay(handle)
                    }
                }

                labeledField("说明") {
                    readOnlyTemplateControl { handle in
                        CodexMultilineTextField(
                            rule: .multilineNote,
                            placeholder: "说明",
                            text: draftTextBinding(\.note),
                            isDisabled: !store.isEditable,
                            readOnlyNotice: handle
                        )
                        .lineLimit(MultilineInputDefaults.promptTemplateNoteLineLimit)
                    }
                }

                if let validationError = store.validationError {
                    messageRow(
                        validationMessage(for: validationError),
                        color: CodexColors.stateStopped,
                        symbol: "exclamationmark.circle.fill"
                    )
                }
            }
            .padding(CodexSpacing.compactField)
        }
        .opacity(store.isEditable ? 1 : 0.56)
    }

    private var detailFooter: some View {
        HStack(spacing: CodexSpacing.contentInline) {
            Label(
                store.isEditable ? (store.isDirty ? "有未保存修改" : "可编辑状态") : "只读状态",
                systemImage: store.isEditable ? "pencil" : "lock.fill"
            )
            .font(CodexTypography.caption)
            .foregroundStyle(.secondary)

            Spacer()

            CodexButton(
                rule: .formFooterCapsule,
                isDisabled: !store.isEditable || !store.isDirty,
                action: { store.discardChanges() }
            ) {
                footerActionLabel(systemImage: "arrow.uturn.backward", title: "放弃修改")
            }
            .help("放弃当前未保存修改")

            CodexButton(
                rule: .formFooterCapsule,
                isDisabled: !store.isEditable || !store.isDirty,
                action: { _ = store.save() }
            ) {
                footerActionLabel(systemImage: "checkmark", title: "保存")
            }
            .help("保存当前用户自定义模板")
        }
        .padding(CodexSpacing.compactField)
    }

    private var emptyListState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(CodexTypography.promptTemplateTitle)
                .foregroundStyle(.secondary)

            Text("没有匹配的提示词模板")
                .font(CodexTypography.tinyControlLabel)

            Text("调整来源、类型或搜索条件后再试。")
                .font(CodexTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "doc.text")
                .font(CodexTypography.panelHeader)
                .foregroundStyle(.secondary)

            Text("选择一个提示词模板")
                .font(CodexTypography.promptTemplateMeta)

            Text("左侧可按来源、类型和关键词筛选。")
                .font(CodexTypography.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var detailTitle: String {
        guard let name = store.draft?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "未命名提示词"
        }

        return name
    }

    private func sidebarIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(CodexTypography.menuPrimary)
            .frame(width: 28, height: 28)
    }

    private func headerActionLabel(systemImage: String, title: String, foregroundColor: Color = .primary) -> some View {
        Label(title, systemImage: systemImage)
            .font(CodexTypography.microControl)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, CodexSpacing.contentInline)
            .padding(.vertical, CodexSpacing.compactVertical)
    }

    private func footerActionLabel(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(CodexTypography.microControl)
            .padding(.horizontal, CodexSpacing.contentInline)
            .padding(.vertical, CodexSpacing.compactVertical)
    }

    private func editor(text: Binding<String>, minHeight: CGFloat) -> some View {
        AppMultilineTextEditor(text: text)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodexColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CodexColors.surfaceStroke, lineWidth: 1)
            )
    }

    private func messageRow(_ message: String, color: Color, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(CodexTypography.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: CodexSpacing.compactInline) {
            Text(label)
                .font(CodexTypography.captionStrong)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.top, CodexSpacing.compactVertical)

            content()
        }
    }

    private func readOnlyTemplateControl<Content: View>(@ViewBuilder _ content: @escaping (CodexReadOnlyNoticeHandle) -> Content) -> some View {
        CodexReadOnlyNoticeHost(
            isReadOnly: !store.isEditable,
            rule: .promptTemplateSystemTemplate,
            content: content
        )
    }

    private var sourceFilterBinding: Binding<PromptTemplateSourceFilter> {
        Binding(
            get: { store.sourceFilter },
            set: { store.sourceFilter = $0 }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTemplate != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteTemplate = nil
                }
            }
        )
    }

    private func typeFilterBinding(_ type: PromptTemplateType) -> Binding<Bool> {
        Binding(
            get: { store.selectedTypes.contains(type) },
            set: { _ in store.toggleTypeFilter(type) }
        )
    }

    private func draftTextBinding(_ keyPath: WritableKeyPath<PromptTemplateDraft, String>) -> Binding<String> {
        Binding(
            get: { store.draft?[keyPath: keyPath] ?? "" },
            set: { value in store.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private var draftTypeBinding: Binding<PromptTemplateType?> {
        Binding(
            get: { store.draft?.type },
            set: { value in store.updateDraft { $0.type = value } }
        )
    }

    private func validationMessage(for error: PromptTemplateValidationError) -> String {
        switch error {
        case .emptyName:
            return "名称不能为空。"
        case .missingType:
            return "类型必须选择一项。"
        case .emptySystemPrompt:
            return "系统提示词不能为空。"
        }
    }

    private func performOrConfirm(_ action: PendingDirtyAction) {
        guard store.isDirty else {
            perform(action)
            return
        }

        pendingAction = action
        isShowingDirtyConfirmation = true
    }

    private func performPendingActionAfterSave() {
        guard let pendingAction else {
            return
        }

        if store.save() {
            self.pendingAction = nil
            perform(pendingAction)
        } else {
            self.pendingAction = nil
        }
    }

    private func performPendingActionAfterDiscard() {
        guard let pendingAction else {
            return
        }

        self.pendingAction = nil
        store.discardChanges()
        perform(pendingAction)
    }

    private func perform(_ action: PendingDirtyAction) {
        switch action {
        case .create:
            store.createTemplate()
        case .copy:
            store.copySelectedTemplate()
        case let .select(id):
            store.select(id)
        case let .rename(id):
            beginRename(id)
        }
    }

    private func beginRename(_ id: UUID) {
        guard let template = store.templates.first(where: { $0.id == id }), template.source == .userCustom else {
            return
        }

        pendingRenameTemplate = template
        renameText = template.name
        isShowingRenamePrompt = true
    }

    private func clearRenamePrompt() {
        pendingRenameTemplate = nil
        renameText = ""
    }
}

private enum PendingDirtyAction: Equatable {
    case create
    case copy
    case select(UUID)
    case rename(UUID)
}

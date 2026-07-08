import CodexPlusCore
import SwiftUI

struct PromptTemplateManagerView: View {
    @ObservedObject private var store: PromptTemplateSettingsStore
    @State private var isShowingDirtyConfirmation = false
    @State private var isShowingRenamePrompt = false
    @State private var pendingAction: PendingDirtyAction?
    @State private var pendingDeleteTemplate: PromptTemplate?
    @State private var pendingRenameTemplate: PromptTemplate?
    @State private var isShowingReadOnlyTemplateNotice = false
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
            TextField("名称", text: $renameText)
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
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Button(action: { performOrConfirm(.create) }) {
                        sidebarIcon("plus")
                    }
                    .buttonStyle(.plain)
                    .codexCircularButtonHitArea()
                    .help("新增用户自定义提示词")
                }

                TextField("搜索名称、说明、系统提示词、用户提示词", text: $store.searchQuery)
                    .textFieldStyle(.roundedBorder)

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
            .padding(12)
        }
    }

    private var sourceFilter: some View {
        Picker("", selection: sourceFilterBinding) {
            Text("全部").tag(PromptTemplateSourceFilter.all)
            Text("系统内置").tag(PromptTemplateSourceFilter.source(.systemBuiltIn))
            Text("用户自定义").tag(PromptTemplateSourceFilter.source(.userCustom))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var typeFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("类型筛选")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(PromptTemplateType.allCases, id: \.self) { type in
                    Toggle(isOn: typeFilterBinding(type)) {
                        Text(type.shortDisplayName)
                            .font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.button)
                    .help(type.displayName)
                }
            }
        }
    }

    private func templateRow(_ template: PromptTemplate) -> some View {
        Button(action: { performOrConfirm(.select(template.id)) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if store.isDefaultTemplate(template) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                            .help("此类型默认模板")
                    }
                }

                templateMetadataRow(template)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(rowBackground(isSelected: store.selectedTemplateID == template.id))
        }
        .buttonStyle(.plain)
        .codexRoundedButtonHitArea(cornerRadius: 8)
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
                .tint(.blue)
            }
        }
    }

    private func templateMetadataRow(_ template: PromptTemplate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(template.type.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(template.source.displayName)
                .font(.caption2)
                .foregroundStyle(template.source == .systemBuiltIn ? .green : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
    }

    @ViewBuilder
    private var detailPane: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.settingsCornerRadius) {
            if store.draft == nil {
                emptyDetailState
            } else {
                ZStack {
                    VStack(spacing: 0) {
                        detailHeader

                        Divider()
                            .overlay(.white.opacity(0.08))

                        detailForm

                        Spacer(minLength: 0)

                        Divider()
                            .overlay(.white.opacity(0.08))

                        detailFooter
                    }

                    if isShowingReadOnlyTemplateNotice {
                        readOnlyTemplateNotice
                    }
                }
                .onChange(of: store.isEditable) {
                    if store.isEditable {
                        isShowingReadOnlyTemplateNotice = false
                    }
                }
            }
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detailTitle)
                    .font(.system(size: 20, weight: .semibold))

                Text(store.isEditable ? "用户自定义提示词，可编辑并保存。" : "系统内置提示词不可直接编辑，可复制为用户模板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Button(action: { performOrConfirm(.copy) }) {
                headerActionLabel(
                    systemImage: "doc.on.doc",
                    title: store.isEditable ? "复制" : "复制为用户模板",
                    foregroundColor: .blue
                )
            }
            .buttonStyle(.plain)
            .codexCapsuleButtonHitArea()
            .help("复制当前模板为用户自定义模板")

            if let selectedTemplate = store.selectedTemplate {
                Button(action: { store.setDefaultTemplate(selectedTemplate.id) }) {
                    headerActionLabel(
                        systemImage: store.isDefaultTemplate(selectedTemplate) ? "checkmark.seal.fill" : "checkmark.seal",
                        title: store.isDefaultTemplate(selectedTemplate) ? "当前默认" : "设为默认",
                        foregroundColor: .blue
                    )
                }
                .buttonStyle(.plain)
                .help("设为“\(selectedTemplate.type.shortDisplayName)”类型默认模板")
                .disabled(store.isDefaultTemplate(selectedTemplate))
            }

            if store.isEditable {
                Button(role: .destructive) {
                    pendingDeleteTemplate = store.selectedTemplate
                } label: {
                    headerActionLabel(systemImage: "trash", title: "删除", foregroundColor: .red)
                }
                .buttonStyle(.plain)
                .codexCapsuleButtonHitArea()
                .help("删除当前用户自定义模板")
            }
        }
        .padding(18)
    }

    private var detailForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let errorMessage = store.errorMessage {
                    messageRow(errorMessage, color: .red, symbol: "exclamationmark.triangle.fill")
                }

                labeledField("名称 *") {
                    readOnlyInputArea {
                        TextField("模板名称", text: draftTextBinding(\.name))
                            .textFieldStyle(.roundedBorder)
                            .disabled(!store.isEditable)
                    }
                }

                labeledField("类型 *") {
                    readOnlyInputArea {
                        Picker("", selection: draftTypeBinding) {
                            Text("请选择类型")
                                .tag(Optional<PromptTemplateType>.none)

                            ForEach(PromptTemplateType.allCases, id: \.self) { type in
                                Text(type.displayName)
                                    .tag(Optional(type))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(!store.isEditable)
                    }
                }

                labeledField("系统提示词 *") {
                    readOnlyInputArea {
                        editor(text: draftTextBinding(\.systemPrompt), minHeight: 140)
                            .disabled(!store.isEditable)
                    }
                }

                labeledField("用户提示词") {
                    readOnlyInputArea {
                        editor(text: draftTextBinding(\.userPrompt), minHeight: 100)
                            .disabled(!store.isEditable)
                    }
                }

                labeledField("说明") {
                    readOnlyInputArea {
                        AppMultilineTextField(
                            placeholder: "说明",
                            text: draftTextBinding(\.note),
                            lineLimit: MultilineInputDefaults.promptTemplateNoteLineLimit
                        )
                            .disabled(!store.isEditable)
                    }
                }

                if let validationError = store.validationError {
                    messageRow(
                        validationMessage(for: validationError),
                        color: .orange,
                        symbol: "exclamationmark.circle.fill"
                    )
                }
            }
            .padding(18)
        }
        .opacity(store.isEditable ? 1 : 0.56)
    }

    private var readOnlyTemplateNotice: some View {
        Text("系统内置提示词为只读内容。如需修改，请先创建用户自定义提示词。")
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

    private var detailFooter: some View {
        HStack(spacing: 12) {
            Label(
                store.isEditable ? (store.isDirty ? "有未保存修改" : "可编辑状态") : "只读状态",
                systemImage: store.isEditable ? "pencil" : "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button(action: store.discardChanges) {
                footerActionLabel(systemImage: "arrow.uturn.backward", title: "放弃修改")
            }
            .buttonStyle(.plain)
            .codexCapsuleButtonHitArea()
            .help("放弃当前未保存修改")
            .disabled(!store.isEditable || !store.isDirty)

            Button(action: { _ = store.save() }) {
                footerActionLabel(systemImage: "checkmark", title: "保存")
            }
            .buttonStyle(.plain)
            .codexCapsuleButtonHitArea()
            .help("保存当前用户自定义模板")
            .disabled(!store.isEditable || !store.isDirty)
        }
        .padding(18)
    }

    private var emptyListState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text("没有匹配的提示词模板")
                .font(.system(size: 14, weight: .semibold))

            Text("调整来源、类型或搜索条件后再试。")
                .font(.caption)
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
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("选择一个提示词模板")
                .font(.system(size: 16, weight: .semibold))

            Text("左侧可按来源、类型和关键词筛选。")
                .font(.caption)
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
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .glassEffect(.regular, in: Circle())
    }

    private func headerActionLabel(systemImage: String, title: String, foregroundColor: Color = .primary) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .codexCapsuleButtonHitArea()
    }

    private func footerActionLabel(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule(style: .continuous))
            .codexCapsuleButtonHitArea()
    }

    private func editor(text: Binding<String>, minHeight: CGFloat) -> some View {
        AppMultilineTextEditor(text: text)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func messageRow(_ message: String, color: Color, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.top, 7)

            content()
        }
    }

    private func readOnlyInputArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .overlay {
                if !store.isEditable {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: showReadOnlyTemplateNotice)
                }
            }
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

    private func showReadOnlyTemplateNotice() {
        guard !store.isEditable else {
            return
        }
        guard !isShowingReadOnlyTemplateNotice else {
            return
        }

        withAnimation(.easeOut(duration: 0.16)) {
            isShowingReadOnlyTemplateNotice = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeIn(duration: 0.2)) {
                isShowingReadOnlyTemplateNotice = false
            }
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

import CodexPlusCore
import SwiftUI

struct PromptTemplateManagerView: View {
    @StateObject private var store: PromptTemplateSettingsStore
    @State private var isShowingDeleteConfirmation = false

    init(repository: any PromptTemplateRepository) {
        _store = StateObject(wrappedValue: PromptTemplateSettingsStore(repository: repository))
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
        .alert("删除提示词模板？", isPresented: $isShowingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteSelectedTemplate()
            }
        } message: {
            Text("这个操作只会删除用户自定义提示词模板，系统内置提示词不会被删除。")
        }
    }

    private var sidebar: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.settingsCornerRadius) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("提示词模板")
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Button(action: store.reload) {
                        sidebarIcon("arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("重新加载提示词模板")

                    Button(action: store.createTemplate) {
                        sidebarIcon("plus")
                    }
                    .buttonStyle(.plain)
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
        Picker("来源", selection: sourceFilterBinding) {
            Text("全部").tag(PromptTemplateSourceFilter.all)
            Text("系统内置").tag(PromptTemplateSourceFilter.source(.systemBuiltIn))
            Text("用户自定义").tag(PromptTemplateSourceFilter.source(.userCustom))
        }
        .pickerStyle(.segmented)
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
        Button(action: { store.select(template.id) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text("类型  \(template.type.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("来源  \(template.source.displayName)")
                    .font(.caption2)
                    .foregroundStyle(template.source == .systemBuiltIn ? .green : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(rowBackground(isSelected: store.selectedTemplateID == template.id))
        }
        .buttonStyle(.plain)
        .help(template.name)
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

            Button(action: store.copySelectedTemplate) {
                headerActionLabel(
                    systemImage: "doc.on.doc",
                    title: store.isEditable ? "复制" : "复制为用户模板"
                )
            }
            .buttonStyle(.plain)
            .help("复制当前模板为用户自定义模板")

            if store.isEditable {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    headerActionLabel(systemImage: "trash", title: "删除")
                }
                .buttonStyle(.plain)
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
                    TextField("模板名称", text: draftTextBinding(\.name))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!store.isEditable)
                }

                labeledField("类型 *") {
                    Picker("类型", selection: draftTypeBinding) {
                        Text("请选择类型")
                            .tag(Optional<PromptTemplateType>.none)

                        ForEach(PromptTemplateType.allCases, id: \.self) { type in
                            Text(type.displayName)
                                .tag(Optional(type))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(!store.isEditable)
                }

                labeledField("系统提示词 *") {
                    editor(text: draftTextBinding(\.systemPrompt), minHeight: 140)
                        .disabled(!store.isEditable)
                }

                labeledField("用户提示词") {
                    editor(text: draftTextBinding(\.userPrompt), minHeight: 100)
                        .disabled(!store.isEditable)
                }

                labeledField("说明") {
                    TextField("说明", text: draftTextBinding(\.note), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .disabled(!store.isEditable)
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
            .help("放弃当前未保存修改")
            .disabled(!store.isEditable || !store.isDirty)

            Button(action: store.save) {
                footerActionLabel(systemImage: "checkmark", title: "保存")
            }
            .buttonStyle(.plain)
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

    private func headerActionLabel(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule(style: .continuous))
    }

    private func footerActionLabel(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: Capsule(style: .continuous))
    }

    private func editor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(8)
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

    private var sourceFilterBinding: Binding<PromptTemplateSourceFilter> {
        Binding(
            get: { store.sourceFilter },
            set: { store.sourceFilter = $0 }
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
}

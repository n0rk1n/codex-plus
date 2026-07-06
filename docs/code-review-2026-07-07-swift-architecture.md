# Codex Plus Swift 代码审查

日期：2026-07-07

审查范围：`Sources/`、`Tests/`、`Package.swift` 中除归档相关实现外的 Swift 代码；明确排除 `archives/` 历史包、`Sources/CodexPlusCore/Archive/`、`Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift` 的细节实现。归档调用对主架构的影响会在需要时提及。

验证基线：

- `swift test`：构建成功后返回 `no tests found`，原因是 `Package.swift` 把 `CodexPlusCoreTests` 定义成 `executableTarget`，不是 `testTarget`。
- `swift run CodexPlusCoreTests`：通过，`531 assertions`。
- 普通沙箱下 Swift 会因为不能写 `~/.cache/clang/ModuleCache` 失败；提升权限后可运行。

## 总体判断

项目的基础功能不是空壳，核心能力已经搭起来了：SwiftPM 包结构清晰，`CodexPlusCore` 与 `CodexPlusApp` 大体分层正确；执行层已有 `ExecutionEngine` / `ExecutionHandle` 抽象；SQLite、Codex CLI 事件解析、面板定位、Dashboard tile 拖拽等也有可测试的 policy 或 service 类型。

但当前架构处在从旧紧凑面板向新 Workbench 迁移的中间态，最大问题不是某几个命名，而是主流程没有收敛。`WindowCoordinator` 同时持有旧 `ConversationCoordinator + CodexRunController + SidePanel` 和新 `WorkbenchStore + ExecutionEngine + WorkbenchPanel` 两套会话/执行链路；`WorkbenchStore` 又承担状态、业务规则、执行、归档入口、持久化协调、错误处理和 snapshot 组装。继续在这个形态上堆功能，会让新功能每次都要猜“该接旧链路还是新链路”。

结论：抽象方向是对的，但抽象边界还不稳；基础功能有雏形且测试能跑，但“可维护的产品骨架”还未完全成型。

## 主要问题

### P0：两套会话执行架构并存，主流程不唯一

证据：

- `WindowCoordinator` 同时持有 `conversationCoordinator`、`workbenchStore`、`runController`，并实例化 `SidePanelController`、`CompactPanelController`、`WorkbenchPanelController`、`WorkbenchLauncherPanelController`。
- 全局快捷键现在只调用 `workbenchPanelController.toggle()`，但 `handleLegacyGlobalShortcutRouting()`、`showCompactPanel()`、`showSidePanel()`、旧的 `startConversation()`、`handleFollowUp()`、`startCodexRun()` 仍然保留。
- 新 Workbench 通过 `WorkbenchStore.startEngineRun()` 走 `ExecutionEngine`；旧 SidePanel 通过 `WindowCoordinator.startCodexRun()` 走 `CodexRunController`。

风险：

- 同一概念有两套状态源：`ConversationCoordinatorSnapshot` 与 `WorkbenchSnapshot`。
- 同一行为有两套实现：创建会话、跟进 prompt、停止运行、归档、权限模式。
- 后续改 Bug 很容易只改一条链路，另一条链路继续保留旧行为。

建议：

1. 明确 Workbench 是唯一主体验后，建立迁移删除清单。
2. 删除或隔离 legacy SidePanel/CompactPanel 会话执行链路，至少先让旧入口只作为 Workbench 的薄启动器，不再持有独立会话状态。
3. 把 `CodexRunController` 标记为 legacy 或迁移到 `ExecutionEngine` 体系下，避免两套 stop/finish 语义继续漂移。

### P0：`WorkbenchStore` 职责过载，已经成为业务单体

证据：

- `WorkbenchStore` 约 589 行。
- 它直接处理项目创建、草稿选择、会话创建、follow-up、运行停止、归档确认、归档搜索、active selection、snapshot 投影、持久化和执行回调。
- `saveProject()`、`saveConversation()`、`submitPrompt()`、`searchArchives()` 等路径把错误吞成 `false` 或空结果，没有统一错误模型。

风险：

- Store 既是 reducer，又是 use case 层，又是 repository transaction coordinator。
- UI 只能看到状态消失或按钮没反应，看不到具体失败原因。
- 持久化、执行和 UI 状态更新交织，后续引入更多状态时会明显变脆。

建议拆分：

- `WorkbenchStore`：保留 `@Published snapshot` 和外部 intent API。
- `ConversationSessionService`：创建、追加 prompt、运行状态转移、active conversation 选择。
- `ProjectSelectionService` 或纯 policy：项目选择、空项目隐藏、active fallback。
- `RunOrchestrator`：封装 `ExecutionEngine` handle、start/stop/finish/event 映射。
- `WorkbenchErrorState`：把无法创建 workspace、保存失败、执行启动失败、归档失败暴露到 snapshot。

### P1：持久化协议过宽，SQLite 实现过大

证据：

- `CodexPlusRepository` 一个协议包含 project、conversation、archive、memory card、memory source、attachment 全部接口。
- extension 里给 memory/attachment 提供默认实现并抛 `UnsupportedRepositoryOperation`，说明协议已经不能代表单一能力。
- `SQLiteCodexPlusRepository` 同时承担 SQL、事务、事件编码、事件解码、字段解析、archive/memory/attachment CRUD。

风险：

- 单元测试 fake repository 必须实现很多无关方法，或依赖默认 unsupported 行为。
- 任何 schema 变化都集中冲击一个大文件。
- 编码/解码逻辑难以独立 fuzz 或回归测试。

建议：

- 拆成 `ProjectRepository`、`ConversationRepository`、`ArchiveRepository`、`MemoryRepository`、`AttachmentRepository`。
- SQLite 侧按 table group 拆成小 gateway，例如 `SQLiteConversationStore`、`SQLiteMemoryStore`。
- 把 `EncodedConversationEvent` / `DecodedConversationEvent` 移到独立 `ConversationEventCodec`，并使用 `Codable` 明确定义 payload，而不是 `[String: Any]`。

### P1：错误处理对产品状态不可见

证据：

- `WorkbenchStore.init` 用 `(try? repository.loadProjects()) ?? []` 和 `(try? repository.loadConversations()) ?? []`。
- `submitPrompt()` 创建默认 workspace 失败时直接 `return`。
- `saveProject()`、`saveConversation()` 捕获后只返回 `false`。
- `searchArchives()` 失败后返回空数组。

风险：

- 数据库损坏、权限错误、磁盘满、workspace 创建失败都会表现成“没有数据”或“按钮无响应”。
- 用户无法判断是没有内容，还是读取失败。
- 也会让测试倾向于只验证 happy path，而不是产品可恢复性。

建议：

- 在 `WorkbenchSnapshot` 增加 `errorBanner` 或 `lastError`。
- Store 内部使用明确的 `WorkbenchStoreError`，保留底层错误描述用于日志。
- 对启动加载失败、保存失败、workspace 创建失败、执行启动失败分别建测试。

### P1：测试基础设施不标准，且存在大量源码字符串断言

证据：

- `Package.swift` 将 `CodexPlusCoreTests` 定义为 `executableTarget`，所以 `swift test` 报 `no tests found`。
- `Tests/CodexPlusCoreTests/main.swift` 约 3125 行，包含大量 `String(contentsOf:)` + `text.contains(...)` 的结构检查。

风险：

- CI 和常规 SwiftPM 工具默认不会跑这些测试。
- 源码字符串断言会把实现细节固定住，正常重构会触发大量假失败。
- 测试入口过大，新增测试缺少自然归属。

建议：

1. 把 `CodexPlusCoreTests` 改成 `.testTarget`，保留必要时的自定义 runner 但不要替代 `swift test`。
2. 把源码字符串断言迁移为行为测试或 snapshot-level 测试。
3. 按主题拆测试文件：`ProcessCodexRunnerTests`、`CodexEventParserTests`、`WorkbenchStoreTests`、`PersistenceTests`、`LayoutPolicyTests`。

### P1：App 层 coordinator 仍承担过多窗口和业务胶水

证据：

- `WindowCoordinator` 约 508 行，包含监控启动、全局快捷键、旧/新 panel 生命周期、会话业务、执行启动、权限确认、workspace 文件系统创建、NSOpenPanel、归档、窗口移动路由。
- `SidePanelController` 约 386 行，混合 panel frame、edge affordance、dismiss monitor、mouse exit、内容安装。

风险：

- macOS 窗口生命周期问题和业务问题耦合，排查会困难。
- Legacy 代码继续留在主 coordinator，会让“当前产品形态”不清晰。

建议：

- `WindowCoordinator` 只保留 app-level wiring：启动 monitors、注册 hotkey、连接 launcher 和 workbench。
- `WorkbenchWindowController` 负责 Workbench panel；`LauncherWindowController` 负责 launcher；旧 SidePanel 若保留，放入 `Legacy/` 命名空间。
- workspace 文件系统创建应归 Core policy/service，不应在 App coordinator 里复制一套。

### P2：模型命名混有历史语义，部分名称不能反映当前架构

例子：

- `ConversationCoordinator`：如果 Workbench 是主线，这个类型已经是 legacy coordinator。
- `WorkbenchStore`：实际是 store + use case + run orchestrator。
- `CodexRunController` 与 `ExecutionEngine`：两个名称都表达“执行 Codex”，但抽象层级不同且并存。
- `ArchiveRequestResult` / `ConversationArchiveResult`：两个归档结果类型分别服务新旧链路，容易混淆。

建议：

- 迁移前短期加命名标识：`LegacyConversationCoordinator`、`LegacyCodexRunController`。
- 新主线命名使用角色词：`WorkbenchStateStore`、`ConversationRunOrchestrator`、`ConversationLifecycleService`。
- 结果类型按 use case 命名：`ArchiveConversationOutcome`。

### P2：并发模型可工作，但仍偏 GCD/锁混合风格

证据：

- `ProcessCodexRunner` 使用 `DispatchQueue.global` 读取 stdout/stderr，`DispatchGroup` 汇合，多个 `NSLock` 包装 buffer/process。
- `CodexRunController` 是 `@MainActor`，但通过 `callbackQueue.async`、`DispatchQueue.main.async`、`MainActor.assumeIsolated` 切回主线程。
- 新 `WorkbenchStore` 使用 `Task { @MainActor in ... }` 处理 `ExecutionEngine` 回调。

判断：

- 目前测试覆盖了基本 stop、并行、stdout/stderr 截断等行为，说明基础实现能跑。
- 但 Swift 6 项目继续扩大后，GCD + `@unchecked Sendable` + `MainActor.assumeIsolated` 会增加并发审计成本。

建议：

- 新主线优先用 `AsyncStream<CodexEvent>` / structured concurrency 表达进程事件。
- `ExecutionEngine.start` 可以演进为返回 `ConversationRun`，其中包含 `events` stream 和 `stop()`。
- 旧 `CodexRunController` 如不再使用，应删除而不是继续维护。

### P2：UI 闭包参数过长，视图动作接口需要聚合

证据：

- `ConversationView` 接收十多个 action closure。
- `SidePanelActions` 聚合了旧面板动作，但仍是 legacy 视图专用。
- 新 `WorkbenchView` 直接把 `store` 方法传给子视图，简单但会让子视图逐步知道太多 store 细节。

建议：

- 对主线 Workbench 建立 `WorkbenchActions` 或让子视图只接收小型 action group，例如 `ProjectStripActions`、`ComposerActions`。
- 子视图只表达用户意图，不直接承担业务分派。

### P3：可见字符串、魔法尺寸和产品配置还需要集中

观察：

- 中英文 UI 字符串混用：旧链路多英文，新 Workbench 有中文。
- 面板尺寸、padding、corner radius、tile 高度多处分散。
- `CodexCommandBuilder` 固定 `--skip-git-repo-check`、`read-only`、`danger-full-access`，目前合理，但未来应有配置边界。

建议：

- 增加 `UIStrings` 或 localization 入口，至少先统一中文主体验。
- 增加 `DesignMetrics` 或按组件聚合 metrics，避免窗口/视图间复制尺寸。
- `CodexCommandBuilder` 增加显式配置结构，方便未来增加 model、profile、approval policy 等参数。

## 模块分工评价

### 做得好的地方

- `CodexPlusCore` 与 `CodexPlusApp` 的总体边界正确：Core 无 AppKit/SwiftUI 依赖，App 层持有窗口和视图。
- 多个纯策略类型值得保留：`ConversationWorkspacePolicy`、`WorkbenchInteractionPolicies`、`DashboardTileLayoutPolicy`、`CompactDashboardTileDragPolicy`、`ConversationTimelineBuilder`。
- 执行层已有依赖反转：`ExecutionEngine` 让 `WorkbenchStoreTests` 能用 `ManualExecutionEngine` 断言请求、停止和完成。
- SQLite 基础封装 `SQLiteDatabase` 简洁，binding 和 row decode 都有集中入口。

### 需要收敛的地方

- `ConversationCoordinator` 与 `WorkbenchStore` 都在表达会话状态管理，应只保留一个主线。
- `CodexRunController` 与 `ExecutionEngine` 都在表达运行控制，应以 `ExecutionEngine` 为主线。
- `WindowCoordinator` 需要从“业务协调器”退回到“窗口装配器”。
- Repository 需要从“全能数据访问协议”拆成按 bounded context 的协议。

## 抽象性与基础能力

抽象性评价：中等偏上，但局部抽象过宽。

- 好抽象：policy、engine、provider、status cache、layout projection。
- 过宽抽象：`CodexPlusRepository`、`WorkbenchStore`。
- 历史抽象：`ConversationCoordinator`、`CodexRunController` 现在更像迁移遗留。

基础功能评价：已具备 MVP 骨架，但缺三个产品级能力。

1. 可见错误状态：现在失败多数静默。
2. 标准测试入口：`swift test` 不能发现测试。
3. 主架构唯一性：Workbench 与 legacy 面板链路需要合并或删除。

## 推荐改造顺序

### 第一阶段：收敛主线，降低认知负担

目标：让所有新功能只接 Workbench 主线。

- 删除或隔离 `WindowCoordinator` 中的 legacy routing、SidePanel conversation run、CompactPanel submit path。
- 如暂时不能删，把 legacy 文件移动到 `Sources/CodexPlusApp/Legacy/`，类型改名带 `Legacy`。
- `WindowCoordinator.handleGlobalShortcut()` 保持只打开 Workbench，并删除不可达私有方法。

验收：

- 搜索 `ConversationCoordinator` 在 App 主线中不再被使用，或只在 legacy namespace 中使用。
- 新会话、follow-up、stop 全部只走 `WorkbenchStore + ExecutionEngine`。

### 第二阶段：拆 `WorkbenchStore`

目标：Store 只负责状态发布和 intent 转发。

- 抽出 `ConversationLifecycleService`。
- 抽出 `RunOrchestrator`。
- 抽出 `ProjectSelectionPolicy`。
- 增加 `WorkbenchSnapshot.error`。

验收：

- `WorkbenchStore` 降到 200-250 行左右。
- run start/stop/finish 有独立测试。
- workspace 创建失败、repository 保存失败会进入 snapshot error。

### 第三阶段：重整持久化

目标：数据访问协议按能力拆分。

- 拆 repository 协议。
- 拆 SQLite 文件。
- 独立 `ConversationEventCodec`。
- 对 schema migration 增加版本演进测试。

验收：

- Workbench store 测试 fake 只实现 conversation/project 需要的协议。
- 事件 payload 编解码有独立 round-trip 测试。

### 第四阶段：测试和工程化

目标：让标准 Swift 工具直接工作。

- 将 `CodexPlusCoreTests` 改为 `.testTarget`。
- 把 `main.swift` 中的源码字符串测试改成行为测试。
- 添加 CI 脚本：`swift test` 或临时 `swift run CodexPlusCoreTests`，但推荐前者。

验收：

- `swift test` 直接执行全部测试。
- 重命名私有方法不会导致 UI 集成测试大面积失败。

## 具体修改建议清单

1. 删除 `WindowCoordinator.handleLegacyGlobalShortcutRouting()` 及其只服务 legacy 的调用链，或整体移动到 `LegacyWindowCoordinator`.
2. 让 `AppDelegate` 不再创建 `ConversationCoordinator` 和 `ProcessCodexRunner` 的旧链路依赖；只创建 `WorkbenchStore` 所需依赖。
3. 给 `WorkbenchStore` 增加 `lastError`，替换所有静默 `return`。
4. 将 `WorkbenchStore.displayEvent(from:)` 与 `ConversationCoordinator.displayEvent(from:)` 合并为 `CodexEventDisplayMapper`。
5. 将 `ConversationWorkspacePolicy.createDefaultWorkspaceDirectory()` 作为唯一默认 workspace 创建入口，删除 `WindowCoordinator.createDefaultWorkspaceDirectory()` 的重复实现。
6. 拆 `CodexPlusRepository` 协议，先从 `MemoryRepository` / `AttachmentRepository` 拆起，因为它们已经通过 default unsupported 暴露出边界问题。
7. 把 `EncodedConversationEvent` 和 `DecodedConversationEvent` 从 repository 文件移出。
8. 把 `CodexPlusCoreTests` 改为 `testTarget`，保留 `expect` 风格也可以，但入口应由 SwiftPM test discovery 执行。
9. 逐步删除源码字符串断言，尤其是检查某个文件是否包含某段私有实现的测试。
10. 建立命名规则：主线不使用 `legacy` 未标注的旧类型；主线状态统一叫 `WorkbenchSnapshot`，旧状态统一标记 legacy。

## 优先级结论

短期最该做的不是继续加 feature，而是先确定主线架构：以 Workbench 为唯一会话体验，删除旧 SidePanel 执行链路。完成这一步后，再拆 `WorkbenchStore` 和 repository。否则每个新功能都会被迫同时考虑两个状态源、两个执行控制器、两个 UI 行为面，技术债会继续放大。

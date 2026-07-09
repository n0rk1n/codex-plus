import Foundation

public enum MarkdownArchiveRenderer {
    public static func render(conversation: ConversationSession, projectName: String) -> String {
        render(
            conversation: conversation,
            projectName: projectName,
            compressionState: nil,
            assembledModelInput: nil
        )
    }

    public static func render(
        conversation: ConversationSession,
        projectName: String,
        compressionState: ConversationCompressionState?,
        assembledModelInput: String?
    ) -> String {
        var output: [String] = [
            "# \(conversation.title)",
            "",
            "项目：\(projectName)",
            "工作目录：\(conversation.workspacePath)",
            "状态：\(conversation.state.rawValue)",
            "",
            "## 事件",
            ""
        ]

        for event in conversation.events {
            output.append(contentsOf: lines(for: event))
            output.append("")
        }

        if let compressionState,
           compressionState.hasArchiveMetadata {
            output.append("")
            output.append(contentsOf: compressionLines(
                state: compressionState,
                assembledModelInput: assembledModelInput ?? ""
            ))
        }

        if output.last == "" {
            output.removeLast()
        }

        return output.joined(separator: "\n")
    }

    private static func lines(for event: ConversationDisplayEvent) -> [String] {
        switch event {
        case let .userPrompt(_, text):
            return ["### 用户", text]
        case let .status(_, text):
            return ["### 状态", text]
        case let .assistantMessage(_, text):
            return ["### Codex", text]
        case let .command(_, executionID, command, status):
            var output = ["### 命令", command, "状态：\(status.rawValue)"]
            if let executionID {
                output.append("执行 ID：\(executionID)")
            }
            return output
        case let .error(_, text):
            return ["### 错误", text]
        case let .parseWarning(_, text):
            return ["### 解析警告", text]
        }
    }

    private static func compressionLines(
        state: ConversationCompressionState,
        assembledModelInput: String
    ) -> [String] {
        var output: [String] = [
            "## Context Compression",
            "",
            "### Active Model Input At Archive Time",
            "",
            assembledModelInput,
            "",
            "### Rounds"
        ]

        for round in state.rounds.sorted(by: roundSort) {
            output.append("- \(round.id.uuidString.lowercased()) index=\(round.roundIndex)")
        }

        output.append("")
        output.append("### Versions")
        for version in state.versions.sorted(by: versionSort) {
            output.append("- \(version.id.uuidString.lowercased()) \(version.operation.rawValue) \(version.status.rawValue) scope=\(version.scopeKind.rawValue)")
            if !version.content.isEmpty {
                output.append("  content: \(version.content)")
            }
            if let errorMessage = version.errorMessage, !errorMessage.isEmpty {
                output.append("  error: \(errorMessage)")
            }
        }

        output.append("")
        output.append("### Sources")
        for source in state.versionSources.sorted(by: sourceSort) {
            output.append("- version=\(source.versionID.uuidString.lowercased()) source=\(source.sourceID.uuidString.lowercased()) kind=\(source.sourceKind.rawValue) ordinal=\(source.ordinal)")
        }

        output.append("")
        output.append("### Active Versions")
        for active in state.activeVersions.sorted(by: activeSort) {
            output.append("- active=\(active.activeVersionID.uuidString.lowercased()) round=\(active.roundID?.uuidString.lowercased() ?? "nil") range=\(active.rangeID?.uuidString.lowercased() ?? "nil")")
        }

        if !state.inputs.isEmpty {
            output.append("")
            output.append("### Inputs")
            for input in state.inputs.sorted(by: inputSort) {
                output.append("- \(input.id.uuidString.lowercased()) mode=\(input.mode.rawValue) provider=\(input.providerName) model=\(input.providerModel)")
                if !input.userInstruction.isEmpty {
                    output.append("  instruction: \(input.userInstruction)")
                }
                if !input.inputSnapshot.isEmpty {
                    output.append("  snapshot: \(input.inputSnapshot)")
                }
            }
        }

        return output
    }

    private static func roundSort(_ lhs: CompressionRound, _ rhs: CompressionRound) -> Bool {
        if lhs.roundIndex != rhs.roundIndex {
            return lhs.roundIndex < rhs.roundIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func versionSort(_ lhs: CompressionVersion, _ rhs: CompressionVersion) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func sourceSort(_ lhs: CompressionVersionSource, _ rhs: CompressionVersionSource) -> Bool {
        if lhs.ordinal != rhs.ordinal {
            return lhs.ordinal < rhs.ordinal
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func activeSort(_ lhs: CompressionActiveVersion, _ rhs: CompressionActiveVersion) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }

    private static func inputSort(_ lhs: CompressionInputRecord, _ rhs: CompressionInputRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension ConversationCompressionState {
    var hasArchiveMetadata: Bool {
        !versions.isEmpty
            || !versionSources.isEmpty
            || !lineageEdges.isEmpty
            || !activeVersions.isEmpty
            || !inputs.isEmpty
            || !tombstones.isEmpty
    }
}

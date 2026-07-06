import Foundation

public enum MarkdownArchiveRenderer {
    public static func render(conversation: ConversationSession, projectName: String) -> String {
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
}

import Foundation

final class ContextCompressionOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ event: CodexEvent) {
        guard case let .agentMessage(text) = event else {
            return
        }

        lock.lock()
        defer {
            lock.unlock()
        }
        messages.append(text)
    }

    func output() -> String {
        lock.lock()
        defer {
            lock.unlock()
        }

        return messages
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import Combine
import Foundation

@MainActor
public final class ConversationCoordinator: ObservableObject {
    @Published public private(set) var activeConversation: ConversationSession?
    @Published public private(set) var preferredSide: SideAttachment = .right

    public init() {}

    @discardableResult
    public func startConversation(prompt: String) -> ConversationSession {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ConversationSession(
            prompt: trimmedPrompt,
            events: [
                .userPrompt(id: UUID(), text: trimmedPrompt)
            ]
        )
        activeConversation = session
        return session
    }

    public func shortcutDecision() -> ShortcutDecision {
        guard let activeConversation else {
            return .openFreshEntry
        }

        if activeConversation.state == .running ||
            activeConversation.isPinned ||
            activeConversation.isExplicitlyKept {
            return .recallExisting(activeConversation.id)
        }

        return .openFreshEntry
    }

    public func markRunning(_ id: UUID) {
        updateActiveConversation(id) { session in
            session.state = .running
        }
    }

    public func markCompleted(_ id: UUID) {
        markTerminal(id, state: .completed)
    }

    public func markFailed(_ id: UUID) {
        markTerminal(id, state: .failed)
    }

    public func markStopped(_ id: UUID) {
        markTerminal(id, state: .stopped)
    }

    public func setPermissionMode(_ permissionMode: PermissionMode, for id: UUID) {
        updateActiveConversation(id) { session in
            session.permissionMode = permissionMode
        }
    }

    public func setPinned(_ isPinned: Bool, for id: UUID) {
        updateActiveConversation(id) { session in
            session.isPinned = isPinned
        }
    }

    public func setExplicitlyKept(_ isExplicitlyKept: Bool, for id: UUID) {
        updateActiveConversation(id) { session in
            session.isExplicitlyKept = isExplicitlyKept
        }
    }

    public func togglePreferredSide() {
        preferredSide.toggle()
    }

    public func appendCodexEvent(_ event: CodexEvent, to id: UUID) {
        updateActiveConversation(id) { session in
            session.events.append(Self.displayEvent(from: event))
        }
    }

    private func markTerminal(_ id: UUID, state: ConversationRunState) {
        updateActiveConversation(id) { session in
            session.state = state
            session.permissionMode = .semiAutomatic
        }
    }

    private func updateActiveConversation(
        _ id: UUID,
        _ update: (inout ConversationSession) -> Void
    ) {
        guard var session = activeConversation, session.id == id else {
            return
        }

        update(&session)
        activeConversation = session
    }

    private static func displayEvent(from event: CodexEvent) -> ConversationDisplayEvent {
        switch event {
        case let .threadStarted(threadID):
            return .status(id: UUID(), text: "Thread started: \(threadID)")
        case .turnStarted:
            return .status(id: UUID(), text: "Turn started")
        case .turnCompleted:
            return .status(id: UUID(), text: "Turn completed")
        case let .turnFailed(message):
            return .error(id: UUID(), text: message)
        case let .agentMessage(text):
            return .assistantMessage(id: UUID(), text: text)
        case let .command(_, command, status):
            return .command(id: UUID(), command: command, status: status)
        case let .error(message):
            return .error(id: UUID(), text: message)
        case let .raw(text):
            return .status(id: UUID(), text: text)
        case let .parseWarning(text):
            return .parseWarning(id: UUID(), text: text)
        }
    }
}

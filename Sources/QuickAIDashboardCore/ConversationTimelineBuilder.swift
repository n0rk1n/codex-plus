import Foundation

public enum ConversationTimelineItem: Equatable, Identifiable, Sendable {
    case event(ConversationDisplayEvent)
    case technicalGroup(id: UUID, events: [ConversationDisplayEvent])

    public var id: UUID {
        switch self {
        case let .event(event):
            return event.id
        case let .technicalGroup(id, _):
            return id
        }
    }
}

public enum ConversationTimelineBuilder {
    public static func items(from events: [ConversationDisplayEvent]) -> [ConversationTimelineItem] {
        var items: [ConversationTimelineItem] = []
        var technicalEvents: [ConversationDisplayEvent] = []

        func flushTechnicalEvents() {
            guard let firstEvent = technicalEvents.first else {
                return
            }

            items.append(.technicalGroup(id: firstEvent.id, events: technicalEvents))
            technicalEvents.removeAll(keepingCapacity: true)
        }

        for event in events {
            if event.isTechnicalTimelineEvent {
                technicalEvents.append(event)
            } else {
                flushTechnicalEvents()
                items.append(.event(event))
            }
        }

        flushTechnicalEvents()
        return items
    }
}

private extension ConversationDisplayEvent {
    var isTechnicalTimelineEvent: Bool {
        switch self {
        case .status, .command, .parseWarning:
            return true
        case .userPrompt, .assistantMessage, .error:
            return false
        }
    }
}

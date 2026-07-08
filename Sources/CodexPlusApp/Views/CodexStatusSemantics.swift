import CodexPlusCore
import SwiftUI

extension ConversationRunState {
    var labelText: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return CodexColors.stateIdle
        case .running:
            return CodexColors.stateRunning
        case .completed:
            return CodexColors.stateCompleted
        case .failed:
            return CodexColors.stateFailed
        case .stopped:
            return CodexColors.stateStopped
        }
    }

    var tabDotTint: Color {
        self == .idle ? tint.opacity(0.45) : tint
    }
}

extension CodexCommandStatus {
    var labelText: String {
        switch self {
        case .inProgress:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .unknown:
            return "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .inProgress:
            return CodexColors.stateRunning
        case .completed:
            return CodexColors.stateCompleted
        case .failed:
            return CodexColors.stateFailed
        case .unknown:
            return CodexColors.stateUnknown
        }
    }
}

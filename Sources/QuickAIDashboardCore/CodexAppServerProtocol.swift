import Foundation

public struct CodexAppServerHandoff: Equatable, Sendable {
    public let threadID: String
    public let sessionID: String?

    public init(threadID: String, sessionID: String?) {
        self.threadID = threadID
        self.sessionID = sessionID
    }

    public var openThreadURL: URL {
        let identifier = sessionID.flatMap { $0.isEmpty ? nil : $0 } ?? threadID
        return URL(string: "codex://threads/\(identifier)")!
    }
}

public struct CodexAppServerHandoffResult: Equatable, Sendable {
    public let succeeded: Bool
    public let message: String?

    public init(succeeded: Bool, message: String? = nil) {
        self.succeeded = succeeded
        self.message = message
    }

    public static func success() -> CodexAppServerHandoffResult {
        CodexAppServerHandoffResult(succeeded: true)
    }

    public static func failure(_ message: String) -> CodexAppServerHandoffResult {
        CodexAppServerHandoffResult(succeeded: false, message: message)
    }
}

public enum CodexAppServerProtocol {
    public static func initializeRequest(id: Int) -> String {
        encode([
            "id": id,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "quick_ai_dashboard",
                    "title": "QuickAI Dashboard",
                    "version": "0.1.0"
                ]
            ]
        ])
    }

    public static func initializedNotification() -> String {
        encode([
            "method": "initialized",
            "params": [:]
        ])
    }

    public static func threadStartRequest(id: Int, permissionMode: PermissionMode) -> String {
        encode([
            "id": id,
            "method": "thread/start",
            "params": [
                "approvalPolicy": approvalPolicy(for: permissionMode),
                "approvalsReviewer": "user",
                "sandbox": sandboxValue(for: permissionMode)
            ]
        ])
    }

    public static func turnStartRequest(id: Int, threadID: String, prompt: String) -> String {
        encode([
            "id": id,
            "method": "turn/start",
            "params": [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": prompt
                    ]
                ]
            ]
        ])
    }

    public static func declineApprovalResponse(id: Int) -> String {
        encode([
            "id": id,
            "result": [
                "decision": "decline"
            ]
        ])
    }

    public static func unsupportedRequestResponse(id: Int, message: String) -> String {
        encode([
            "id": id,
            "error": [
                "code": -32601,
                "message": message
            ]
        ])
    }

    public static func responseID(from line: String) -> Int? {
        intValue(object(from: line)?["id"])
    }

    public static func method(from line: String) -> String? {
        object(from: line)?["method"] as? String
    }

    public static func requestID(from line: String) -> Int? {
        guard method(from: line) != nil else {
            return nil
        }

        return responseID(from: line)
    }

    public static func errorMessage(fromResponse line: String) -> String? {
        guard
            let object = object(from: line),
            let error = object["error"] as? [String: Any]
        else {
            return nil
        }

        return error["message"] as? String ?? "Codex app-server returned an error."
    }

    public static func handoff(fromThreadStartResponse line: String) -> CodexAppServerHandoff? {
        guard
            let object = object(from: line),
            let result = object["result"] as? [String: Any],
            let thread = result["thread"] as? [String: Any],
            let threadID = thread["id"] as? String
        else {
            return nil
        }

        return CodexAppServerHandoff(
            threadID: threadID,
            sessionID: thread["sessionId"] as? String
        )
    }

    public static func isTurnCompletedNotification(_ line: String, threadID: String?) -> Bool {
        guard method(from: line) == "turn/completed" else {
            return false
        }

        guard
            let threadID,
            let params = object(from: line)?["params"] as? [String: Any],
            let notificationThreadID = params["threadId"] as? String
        else {
            return true
        }

        return notificationThreadID == threadID
    }

    public static func errorMessage(fromNotification line: String) -> String? {
        guard method(from: line) == "error" else {
            return nil
        }

        guard
            let params = object(from: line)?["params"] as? [String: Any],
            let error = params["error"]
        else {
            return "Codex app-server reported an error."
        }

        if let errorText = error as? String {
            return errorText
        }

        if
            let errorObject = error as? [String: Any],
            let message = errorObject["message"] as? String {
            return message
        }

        return "Codex app-server reported an error."
    }

    public static func isApprovalRequest(_ line: String) -> Bool {
        guard let method = method(from: line) else {
            return false
        }

        return method == "item/commandExecution/requestApproval" ||
            method == "item/fileChange/requestApproval"
    }

    private static func approvalPolicy(for permissionMode: PermissionMode) -> String {
        switch permissionMode {
        case .semiAutomatic:
            return "on-request"
        case .fullAccess:
            return "never"
        }
    }

    private static func sandboxValue(for permissionMode: PermissionMode) -> String {
        switch permissionMode {
        case .semiAutomatic:
            return "read-only"
        case .fullAccess:
            return "danger-full-access"
        }
    }

    private static func object(from line: String) -> [String: Any]? {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return text
    }
}

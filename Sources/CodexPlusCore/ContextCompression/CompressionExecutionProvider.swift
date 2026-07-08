import Foundation

public struct CompressionExecutionRequest: Equatable, Sendable {
    public var sourceText: String
    public var template: PromptTemplate
    public var userInstruction: String
    public var workingDirectoryURL: URL
    public var permissionMode: PermissionMode
    public var sessionID: UUID

    public init(
        sourceText: String,
        template: PromptTemplate,
        userInstruction: String,
        workingDirectoryURL: URL,
        permissionMode: PermissionMode = .semiAutomatic,
        sessionID: UUID = UUID()
    ) {
        self.sourceText = sourceText
        self.template = template
        self.userInstruction = userInstruction
        self.workingDirectoryURL = workingDirectoryURL
        self.permissionMode = permissionMode
        self.sessionID = sessionID
    }
}

public struct CompressionExecutionSuccess: Equatable, Sendable {
    public var output: String
    public var providerName: String
    public var providerModel: String

    public init(output: String, providerName: String, providerModel: String) {
        self.output = output
        self.providerName = providerName
        self.providerModel = providerModel
    }
}

public struct CompressionExecutionFailure: Equatable, Sendable {
    public var message: String
    public var providerName: String
    public var providerModel: String

    public init(message: String, providerName: String, providerModel: String) {
        self.message = message
        self.providerName = providerName
        self.providerModel = providerModel
    }
}

public enum CompressionExecutionResult: Equatable, Sendable {
    case success(CompressionExecutionSuccess)
    case failure(CompressionExecutionFailure)
}

public protocol CompressionExecutionProvider: Sendable {
    func startCompression(
        request: CompressionExecutionRequest,
        onFinish: @escaping @Sendable (CompressionExecutionResult) -> Void
    ) -> (any ExecutionHandle)?
}

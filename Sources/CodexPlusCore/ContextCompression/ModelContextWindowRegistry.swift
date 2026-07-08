import Foundation

public struct ModelContextWindowProfile: Equatable, Sendable {
    public var modelName: String
    public var contextWindowTokens: Int

    public init(modelName: String, contextWindowTokens: Int) {
        self.modelName = modelName
        self.contextWindowTokens = contextWindowTokens
    }
}

public struct ModelContextWindowRegistry: Sendable {
    private var profilesByModelName: [String: ModelContextWindowProfile]

    public init(profiles: [ModelContextWindowProfile]) {
        self.profilesByModelName = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.modelName.lowercased(), $0) }
        )
    }

    public func profile(for modelName: String) -> ModelContextWindowProfile? {
        profilesByModelName[modelName.lowercased()]
    }
}

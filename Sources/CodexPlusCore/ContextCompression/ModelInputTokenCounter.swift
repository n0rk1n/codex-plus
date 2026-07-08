import Foundation

public protocol ModelInputTokenCounter: Sendable {
    func countTokens(in text: String, modelName: String?) -> Int
}

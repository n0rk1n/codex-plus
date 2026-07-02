import Foundation

public struct LineBuffer: Sendable {
    private var partialLine = ""

    public init() {}

    public mutating func append(_ chunk: String) -> [String] {
        partialLine += chunk

        var lines: [String] = []
        while let newlineRange = partialLine.range(of: "\n") {
            var line = String(partialLine[..<newlineRange.lowerBound])
            if line.last == "\r" {
                line.removeLast()
            }
            lines.append(line)
            partialLine.removeSubrange(..<newlineRange.upperBound)
        }

        return lines
    }

    public mutating func flush() -> String? {
        guard !partialLine.isEmpty else {
            return nil
        }

        let line = partialLine
        partialLine = ""
        return line
    }
}

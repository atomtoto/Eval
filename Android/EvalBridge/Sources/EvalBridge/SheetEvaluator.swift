import Foundation
import EvalCore

/// One evaluated line, reduced to plain values that bridge to Kotlin.
public struct LineResult: Hashable, Sendable {
    public let index: Int
    public let source: String
    /// `expression`, `definition`, `equation`, `comment` or `empty`.
    public let kind: String
    /// `success`, `error` or `neutral`.
    public let status: String
    /// The value as the sheet shows it, when the line asks for it. Never for an
    /// equality, whose verdict is in `message`, as on iOS.
    public let value: String?
    public let message: String?
}

/// Evaluates sheets for the Android app with the same engine as iOS.
public final class SheetEvaluator {
    public init() {}

    public func evaluate(_ source: String) -> [LineResult] {
        NotebookEngine.evaluate(source).lines.map { line in
            LineResult(index: line.id, source: line.source, kind: line.kind.rawValue,
                       status: line.status.rawValue,
                       value: line.requestsValue && line.kind != .equation ? line.formattedValue : nil,
                       message: line.message)
        }
    }
}

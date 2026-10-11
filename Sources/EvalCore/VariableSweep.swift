import Foundation

/// One successful sample of a sweep. `index` is the position among the requested
/// samples, so a jump between two consecutive points marks a gap.
public struct SweepPoint: Sendable, Equatable {
    public let index: Int
    /// The variable, in the unit it was entered in.
    public let x: Double
    /// The result, in SI or in the unit requested with `->`.
    public let y: Double

    public init(index: Int, x: Double, y: Double) {
        self.index = index
        self.x = x
        self.y = y
    }
}

/// Evaluates a sheet again for evenly spaced values of one literal declaration
/// and collects one result line, to plot it against that variable.
public enum VariableSweep {
    public static let maximumCount = 2_000

    /// `count` samples (2 to `maximumCount`) from the lower to the upper bound of
    /// `range`. A sample whose evaluation fails, for example a square root of a
    /// negative number, is skipped. Returns nothing when the variable line is not
    /// an adjustable literal or the indexes are out of range. A cancelled task
    /// stops early with the points computed so far.
    public static func sample(source: String, variableLineIndex: Int, resultLineIndex: Int,
                              range: VariableAdjustmentRange, count: Int = 101) -> [SweepPoint] {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard lines.indices.contains(variableLineIndex), lines.indices.contains(resultLineIndex),
              let variable = AdjustableVariable(source: lines[variableLineIndex]) else { return [] }
        let count = min(max(count, 2), maximumCount)
        let span = range.upperBound - range.lowerBound
        var points: [SweepPoint] = []
        for index in 0..<count {
            if Task.isCancelled { break }
            let x = index == count - 1 ? range.upperBound : range.lowerBound + span * Double(index) / Double(count - 1)
            guard let replaced = variable.source(replacingValue: x) else { continue }
            lines[variableLineIndex] = replaced
            let evaluation = NotebookEngine.evaluate(lines.joined(separator: "\n"))
            let line = evaluation.lines[resultLineIndex]
            guard line.status == .success, let quantity = line.quantity else { continue }
            let y = quantity.value / (line.displayUnit?.scale ?? 1)
            if y.isFinite { points.append(SweepPoint(index: index, x: x, y: y)) }
        }
        return points
    }

    /// The name a line fails on because nothing declares it, as in `y = 2·x`
    /// without a line for `x`: the variable such a line can be plotted against.
    /// Nil for any other line, and for a name that cannot be declared with a number.
    public static func freeVariable(in line: EvaluatedLine) -> String? {
        guard line.status == .error, line.kind == .expression || line.kind == .definition,
              let message = line.message, message.hasPrefix("« "),
              let end = message.range(of: " » n’est ni une variable déclarée") else { return nil }
        let name = String(message[message.index(message.startIndex, offsetBy: 2)..<end.lowerBound])
        guard !name.isEmpty, AdjustableVariable(source: "\(name) = 1") != nil else { return nil }
        return name
    }

    /// Like `sample(source:variableLineIndex:…)`, for a name that the sheet does
    /// not declare: a line `name = value` is put above the sheet for each sample.
    /// `resultLineIndex` is the line of the sheet itself.
    public static func sample(source: String, freeVariable name: String, resultLineIndex: Int,
                              range: VariableAdjustmentRange, count: Int = 101) -> [SweepPoint] {
        let points = sample(source: "\(name) = 1\n" + source, variableLineIndex: 0,
                            resultLineIndex: resultLineIndex + 1, range: range, count: count)
        return points
    }

    /// The runs of consecutive samples: draw each as its own line so that
    /// no segment joins two sides of a gap.
    public static func segments(_ points: [SweepPoint]) -> [[SweepPoint]] {
        var result: [[SweepPoint]] = []
        for point in points {
            if let last = result.last?.last, point.index == last.index + 1 {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }
}

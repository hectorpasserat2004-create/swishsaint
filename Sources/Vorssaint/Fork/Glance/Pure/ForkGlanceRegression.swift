// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Martial

import Foundation

// Glance Focus: the regression under the calibration (plan §8.3). A ridge
// regression over the degree-2 terms of the reduced vector, one per screen
// axis, with λ picked by cross-validation. Pure and small: the calibration
// has a few hundred rows and at most 78 terms, so plain normal equations and
// a Cholesky solve are enough, and every case replays in tests.

enum ForkGlanceRegressionError: Error, Equatable {
    /// Fewer than `ForkGlanceRegression.minimumPoints` rows (or groups, for
    /// the cross-validation): a calibration that stopped too early.
    case tooFewPoints
    /// Nothing to learn from: the inputs lie on a line (the head never
    /// moved), rows of different lengths, non-finite values, no weight left,
    /// or a system the solve cannot invert.
    case degenerate
}

/// One axis's model: `coefficients` weigh `ForkGlanceRegression.expand`'s terms.
struct ForkGlanceRidgeModel: Sendable, Equatable {
    var coefficients: [Double]
    /// The shrinkage it was fitted with (diagnostic).
    var lambda: Double

    /// The predicted value for a reduced vector; NaN when the vector does not
    /// have the length the model was fitted on.
    func predict(_ reduced: [Double]) -> Double {
        let terms = ForkGlanceRegression.expand(reduced)
        guard terms.count == coefficients.count else { return .nan }
        var sum = 0.0
        for index in terms.indices { sum += terms[index] * coefficients[index] }
        return sum
    }
}

enum ForkGlanceRegression {
    /// Below this many rows, a degree-2 fit means nothing (plan §17.1).
    static let minimumPoints = 6
    /// The λ ladder of the cross-validation (plan §8.3).
    static let defaultLambdas: [Double] = [1e-3, 3e-3, 1e-2, 3e-2, 0.1, 0.3, 1]

    /// The degree-2 terms of a reduced vector: 1, each xᵢ, then each xᵢ·xⱼ
    /// with i ≤ j, in that order. 6 components give 28 terms, 11 give 78.
    static func expand(_ reduced: [Double]) -> [Double] {
        let count = reduced.count
        var terms = [Double]()
        terms.reserveCapacity(1 + count + count * (count + 1) / 2)
        terms.append(1)
        terms.append(contentsOf: reduced)
        for i in 0..<count {
            for j in i..<count { terms.append(reduced[i] * reduced[j]) }
        }
        return terms
    }

    /// The number of terms `expand` makes from `count` components.
    static func termCount(_ count: Int) -> Int { 1 + count + count * (count + 1) / 2 }

    /// Minimizes the weighted mean squared error plus `lambda` times the
    /// squared coefficients, the intercept excepted. Dividing the error by the
    /// total weight keeps λ meaningful whatever the number of rows: the inputs
    /// are reduced (unit spread), so λ = 1 roughly halves a coefficient.
    static func fit(inputs: [[Double]], targets: [Double], weights: [Double]? = nil,
                    lambda: Double) throws -> ForkGlanceRidgeModel {
        let design = try Design(inputs: inputs, targets: [targets], weights: weights, groups: nil, folds: 1)
        guard lambda.isFinite, lambda >= 0,
              let solution = design.solve(lambda: lambda, excludingFold: nil) else {
            throw ForkGlanceRegressionError.degenerate
        }
        return ForkGlanceRidgeModel(coefficients: solution[0], lambda: lambda)
    }

    /// Picks λ by `folds`-fold cross-validation, then fits every row with it.
    /// `groups` keeps rows together in one fold: the samples of one
    /// calibration point must never be both learned and tested, or the error
    /// would look better than it is. Without groups, each row is its own.
    /// `residualSD` is the weighted standard deviation of the held-out
    /// residuals with the chosen λ, in the targets' unit. On a tie, the
    /// stronger shrinkage wins: it is the prudent one.
    static func crossValidated(inputs: [[Double]], targets: [Double], weights: [Double]? = nil,
                               groups: [Int]? = nil, lambdas: [Double] = defaultLambdas,
                               folds: Int = 5) throws -> (model: ForkGlanceRidgeModel, residualSD: Double) {
        let result = try crossValidated(inputs: inputs, targets: [targets], weights: weights, groups: groups,
                                        lambdas: lambdas, folds: folds)
        return (result.models[0], result.residualSDs[0])
    }

    /// The same for several targets over the same inputs (the two screen
    /// axes): the costly sums are shared, and each target gets its own λ.
    static func crossValidated(inputs: [[Double]], targets: [[Double]], weights: [Double]? = nil,
                               groups: [Int]? = nil, lambdas: [Double] = defaultLambdas,
                               folds: Int = 5) throws -> (models: [ForkGlanceRidgeModel], residualSDs: [Double]) {
        let ladder = lambdas.filter { $0.isFinite && $0 >= 0 }
        guard !ladder.isEmpty, !targets.isEmpty else { throw ForkGlanceRegressionError.degenerate }
        let design = try Design(inputs: inputs, targets: targets, weights: weights, groups: groups,
                                folds: max(folds, 2))
        guard design.foldCount >= 2 else { throw ForkGlanceRegressionError.tooFewPoints }

        // Held-out weighted squared error, per λ and per target.
        var errors = Array(repeating: Array(repeating: 0.0, count: targets.count), count: ladder.count)
        for (lambdaIndex, lambda) in ladder.enumerated() {
            for fold in 0..<design.foldCount {
                guard let solution = design.solve(lambda: lambda, excludingFold: fold) else {
                    errors[lambdaIndex] = Array(repeating: .infinity, count: targets.count)
                    break
                }
                for row in design.rows(inFold: fold) {
                    for target in targets.indices {
                        let residual = design.targets[target][row] - dot(design.terms[row], solution[target])
                        errors[lambdaIndex][target] += design.weights[row] * residual * residual
                    }
                }
            }
        }

        var models: [ForkGlanceRidgeModel] = []
        var deviations: [Double] = []
        for target in targets.indices {
            // Strongest shrinkage first, so a tie keeps it.
            var best: Int?
            for lambdaIndex in ladder.indices.sorted(by: { ladder[$0] > ladder[$1] }) {
                let error = errors[lambdaIndex][target]
                guard error.isFinite else { continue }
                if best == nil || error < errors[best!][target] * (1 - 1e-9) { best = lambdaIndex }
            }
            guard let best, let solution = design.solve(lambda: ladder[best], excludingFold: nil) else {
                throw ForkGlanceRegressionError.degenerate
            }
            models.append(ForkGlanceRidgeModel(coefficients: solution[target], lambda: ladder[best]))
            deviations.append((errors[best][target] / design.totalWeight).squareRoot())
        }
        return (models, deviations)
    }

    // MARK: Helpers

    /// True when the rows span at least a plane once centered: rows on a
    /// line, or all equal, cannot tell two directions apart. The tolerance is
    /// relative to the rows' own spread.
    static func spansPlane(_ rows: [[Double]]) -> Bool {
        guard let width = rows.first?.count, width >= 1, rows.count >= 3 else { return false }
        var mean = Array(repeating: 0.0, count: width)
        for row in rows { for index in 0..<width { mean[index] += row[index] / Double(rows.count) } }
        let centered = rows.map { row in (0..<width).map { row[$0] - mean[$0] } }
        let norms = centered.map { norm($0) }
        guard let largest = norms.max(), largest > 0, largest.isFinite else { return false }
        let tolerance = largest * 1e-7
        // The first direction, then any row that leaves its line.
        guard let first = centered.indices.max(by: { norms[$0] < norms[$1] }) else { return false }
        let axis = centered[first].map { $0 / norms[first] }
        for row in centered {
            let along = dot(row, axis)
            let off = (0..<width).map { row[$0] - along * axis[$0] }
            if norm(off) > tolerance { return true }
        }
        return false
    }

    static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
        var sum = 0.0
        for index in 0..<min(lhs.count, rhs.count) { sum += lhs[index] * rhs[index] }
        return sum
    }

    private static func norm(_ vector: [Double]) -> Double { dot(vector, vector).squareRoot() }

    /// The expanded rows with their per-fold sums: XᵀWX and XᵀWy are summed
    /// once per fold, and a training set is the total minus one fold, so each
    /// λ and fold costs only a solve.
    private struct Design {
        let terms: [[Double]]
        let targets: [[Double]]
        let weights: [Double]
        let foldOfRow: [Int]
        let foldCount: Int
        let width: Int
        let totalWeight: Double
        private let foldGram: [[Double]]      // per fold, width × width, row-major
        private let foldMoment: [[[Double]]]  // per fold, per target, width
        private let foldWeight: [Double]
        private let gram: [Double]
        private let moment: [[Double]]

        init(inputs: [[Double]], targets: [[Double]], weights: [Double]?, groups: [Int]?, folds: Int) throws {
            guard let inputWidth = inputs.first?.count, inputWidth >= 1 else {
                throw inputs.isEmpty ? ForkGlanceRegressionError.tooFewPoints : ForkGlanceRegressionError.degenerate
            }
            let rowCount = inputs.count
            guard targets.allSatisfy({ $0.count == rowCount }),
                  weights.map({ $0.count == rowCount }) ?? true,
                  groups.map({ $0.count == rowCount }) ?? true,
                  inputs.allSatisfy({ $0.count == inputWidth && $0.allSatisfy(\.isFinite) }),
                  targets.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
                throw ForkGlanceRegressionError.degenerate
            }
            let rowWeights = weights ?? Array(repeating: 1, count: rowCount)
            guard rowWeights.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ForkGlanceRegressionError.degenerate }

            // Rows without weight teach nothing: count and check only the others.
            let kept = (0..<rowCount).filter { rowWeights[$0] > 0 }
            let keptGroups = groups.map { list in kept.map { list[$0] } } ?? kept
            let distinctGroups = Array(Set(keptGroups)).sorted()
            guard kept.count >= ForkGlanceRegression.minimumPoints,
                  distinctGroups.count >= ForkGlanceRegression.minimumPoints else {
                throw ForkGlanceRegressionError.tooFewPoints
            }
            let spread = inputWidth == 1
                ? Set(kept.map { inputs[$0][0] }).count >= 3
                : ForkGlanceRegression.spansPlane(kept.map { inputs[$0] })
            guard spread else { throw ForkGlanceRegressionError.degenerate }

            // Groups are dealt to folds in turn, in their sorted order.
            let foldTotal = min(folds, distinctGroups.count)
            var foldOfGroup: [Int: Int] = [:]
            for (index, group) in distinctGroups.enumerated() { foldOfGroup[group] = index % foldTotal }

            let keptTerms = kept.map { ForkGlanceRegression.expand(inputs[$0]) }
            let keptTargets = targets.map { list in kept.map { list[$0] } }
            let keptWeights = kept.map { rowWeights[$0] }
            let keptFolds = keptGroups.map { foldOfGroup[$0] ?? 0 }
            let width = ForkGlanceRegression.termCount(inputWidth)
            self.terms = keptTerms
            self.targets = keptTargets
            self.weights = keptWeights
            self.foldOfRow = keptFolds
            self.foldCount = foldTotal
            self.width = width
            self.totalWeight = keptWeights.reduce(0, +)

            // Raw buffers: the debug build of the tests checks every subscript,
            // and these loops run a few million times per calibration.
            let size = width * width
            var foldGram = Array(repeating: Array(repeating: 0.0, count: size), count: foldTotal)
            var foldMoment = Array(repeating: Array(repeating: Array(repeating: 0.0, count: width),
                                                    count: targets.count), count: foldTotal)
            var foldWeight = Array(repeating: 0.0, count: foldTotal)
            for fold in 0..<foldTotal {
                let rows = keptTerms.indices.filter { keptFolds[$0] == fold }
                foldGram[fold].withUnsafeMutableBufferPointer { gram in
                    for row in rows {
                        let weight = keptWeights[row]
                        keptTerms[row].withUnsafeBufferPointer { x in
                            for i in 0..<width {
                                let wx = weight * x[i]
                                guard wx != 0 else { continue }
                                let base = i * width
                                for j in i..<width { gram[base + j] += wx * x[j] }
                            }
                        }
                    }
                }
                for row in rows {
                    let weight = keptWeights[row]
                    foldWeight[fold] += weight
                    for target in targets.indices {
                        let wy = weight * keptTargets[target][row]
                        let x = keptTerms[row]
                        for i in 0..<width { foldMoment[fold][target][i] += wy * x[i] }
                    }
                }
            }
            var gram = Array(repeating: 0.0, count: size)
            var moment = Array(repeating: Array(repeating: 0.0, count: width), count: targets.count)
            for fold in 0..<foldTotal {
                for index in 0..<size { gram[index] += foldGram[fold][index] }
                for target in targets.indices {
                    for i in 0..<width { moment[target][i] += foldMoment[fold][target][i] }
                }
            }
            let totalWeight = keptWeights.reduce(0, +)
            guard totalWeight > 0, totalWeight.isFinite else { throw ForkGlanceRegressionError.degenerate }
            self.foldGram = foldGram
            self.foldMoment = foldMoment
            self.foldWeight = foldWeight
            self.gram = gram
            self.moment = moment
        }

        func rows(inFold fold: Int) -> [Int] { terms.indices.filter { foldOfRow[$0] == fold } }

        /// The coefficients per target, trained without `excludingFold`; nil
        /// when the system cannot be solved.
        func solve(lambda: Double, excludingFold: Int?) -> [[Double]]? {
            var matrix = gram
            var rightSides = moment
            var weight = totalWeight
            if let fold = excludingFold {
                for index in matrix.indices { matrix[index] -= foldGram[fold][index] }
                for target in rightSides.indices {
                    for i in 0..<width { rightSides[target][i] -= foldMoment[fold][target][i] }
                }
                weight -= foldWeight[fold]
            }
            guard weight > 0 else { return nil }
            // Mirror the upper triangle, then add the shrinkage (not on the intercept).
            for i in 0..<width {
                for j in 0..<i { matrix[i * width + j] = matrix[j * width + i] }
            }
            for i in 1..<width { matrix[i * width + i] += lambda * weight }
            // A tiny ridge on every term guards a λ of 0 against unused terms.
            let jitter = 1e-12 * weight
            for i in 0..<width { matrix[i * width + i] += jitter }
            guard let factor = ForkGlanceRegression.cholesky(matrix, width) else { return nil }
            return rightSides.map { ForkGlanceRegression.solveCholesky(factor, width, $0) }
        }
    }

    /// The lower factor L of a symmetric positive definite matrix (row-major),
    /// or nil when a pivot is not positive.
    private static func cholesky(_ matrix: [Double], _ width: Int) -> [Double]? {
        var lower = Array(repeating: 0.0, count: width * width)
        let solved = lower.withUnsafeMutableBufferPointer { l -> Bool in
            matrix.withUnsafeBufferPointer { a -> Bool in
                for i in 0..<width {
                    let rowI = i * width
                    for j in 0...i {
                        let rowJ = j * width
                        var sum = a[rowI + j]
                        for k in 0..<j { sum -= l[rowI + k] * l[rowJ + k] }
                        if i == j {
                            guard sum > 0, sum.isFinite else { return false }
                            l[rowI + i] = sum.squareRoot()
                        } else {
                            l[rowI + j] = sum / l[rowJ + j]
                        }
                    }
                }
                return true
            }
        }
        return solved ? lower : nil
    }

    private static func solveCholesky(_ lower: [Double], _ width: Int, _ rightSide: [Double]) -> [Double] {
        var y = Array(repeating: 0.0, count: width)
        for i in 0..<width {
            var sum = rightSide[i]
            for k in 0..<i { sum -= lower[i * width + k] * y[k] }
            y[i] = sum / lower[i * width + i]
        }
        var x = Array(repeating: 0.0, count: width)
        for i in stride(from: width - 1, through: 0, by: -1) {
            var sum = y[i]
            for k in (i + 1)..<width { sum -= lower[k * width + i] * x[k] }
            x[i] = sum / lower[i * width + i]
        }
        return x
    }
}

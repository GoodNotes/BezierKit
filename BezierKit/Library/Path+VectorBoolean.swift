//
//  Path+VectorBoolean.swift
//  BezierKit
//
//  Created by Holmes Futrell on 2/8/21.
//  Copyright © 2021 Holmes Futrell. All rights reserved.
//

import Foundation

public extension Path {
    func subtract(_ other: Path, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Path {
        return performBooleanOperation(.subtract, with: other.reversed(), accuracy: accuracy)
    }

    func union(_ other: Path, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Path {
        guard isEmpty == false else {
            return other
        }
        guard other.isEmpty == false else {
            return self
        }
        return performBooleanOperation(.union, with: other, accuracy: accuracy)
    }

    func intersect(_ other: Path, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Path {
        return performBooleanOperation(.intersect, with: other, accuracy: accuracy)
    }

    func crossingsRemoved(accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Path {
        let intersections = selfIntersections(accuracy: accuracy)
        let augmentedGraph = AugmentedGraph(path1: self, path2: self, intersections: intersections, operation: .removeCrossings)
        return augmentedGraph.performOperation()
    }
}

private extension Path {
    func performBooleanOperation(_ operation: BooleanPathOperation, with other: Path, accuracy: Double) -> Path {
        let intersections = self.intersections(with: other, accuracy: accuracy)
        let augmentedGraph = AugmentedGraph(path1: self, path2: other, intersections: intersections, operation: operation)
        return augmentedGraph.performOperation()
    }
}

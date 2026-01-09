//
//  Path+Projection.swift
//  BezierKit
//
//  Created by Holmes Futrell on 11/23/20.
//  Copyright © 2020 Holmes Futrell. All rights reserved.
//

import Foundation

public extension Path {
    private typealias ComponentTuple = (component: PathComponent, index: Int, upperBound: Double)
    private typealias Candidate = (point: Point, location: IndexedPathLocation)
    private func searchForClosestLocation(to point: Point, maximumDistance: Double, requireBest: Bool) -> (point: Point, location: IndexedPathLocation)? {
        // sort the components by proximity to avoid searching distant components later on
        let tuples: [ComponentTuple] = components.enumerated().map { i, component in
            let boundingBox = component.boundingBox
            let upper = boundingBox.upperBoundOfDistance(to: point)
            return (component: component, index: i, upperBound: upper)
        }.sorted(by: { $0.upperBound < $1.upperBound })
        // iterate through each component and search for closest point
        var bestSoFar: Candidate?
        var maximumDistance = maximumDistance
        for next in tuples {
            guard let projection = next.component.searchForClosestLocation(to: point,
                                                                           maximumDistance: maximumDistance,
                                                                           requireBest: requireBest)
            else {
                continue
            }
            let projectionDistance = distance(point, projection.point)
            assert(projectionDistance <= maximumDistance)
            let candidate = (point: projection.point,
                             location: IndexedPathLocation(componentIndex: next.index,
                                                           locationInComponent: projection.location))
            maximumDistance = projectionDistance
            bestSoFar = candidate
        }
        // return the best answer
        if let best = bestSoFar {
            return (point: best.point, location: best.location)
        }
        return nil
    }

    func project(_ point: Point) -> (point: Point, location: IndexedPathLocation)? {
        return searchForClosestLocation(to: point, maximumDistance: .infinity, requireBest: true)
    }

    func pointIsWithinDistanceOfBoundary(_ point: Point, distance: Double) -> Bool {
        return searchForClosestLocation(to: point, maximumDistance: distance, requireBest: false) != nil
    }
}

public extension PathComponent {
    private func anyLocation(in node: BoundingBoxHierarchy.Node) -> IndexedPathComponentLocation {
        switch node.type {
        case let .leaf(elementIndex):
            return IndexedPathComponentLocation(elementIndex: elementIndex, t: 0)
        case let .internal(startingElementIndex, _):
            return IndexedPathComponentLocation(elementIndex: startingElementIndex, t: 0)
        }
    }

    fileprivate func searchForClosestLocation(to point: Point, maximumDistance: Double, requireBest: Bool) -> (point: Point, location: IndexedPathComponentLocation)? {
        var bestSoFar: IndexedPathComponentLocation?
        var maximumDistance: Double = maximumDistance
        bvh.visit { node, _ in
            guard requireBest == true || bestSoFar == nil else {
                return false // we're done already
            }
            let boundingBox = node.boundingBox
            let lowerBound = boundingBox.lowerBoundOfDistance(to: point)
            guard lowerBound <= maximumDistance else {
                return false // nothing in this node can be within maximum distance
            }
            if requireBest == false {
                let upperBound = boundingBox.upperBoundOfDistance(to: point)
                if upperBound <= maximumDistance {
                    maximumDistance = upperBound // restrict the search to this new upper bound
                    bestSoFar = self.anyLocation(in: node)
                    return false
                }
            }
            if case let .leaf(elementIndex) = node.type {
                let curve = self.element(at: elementIndex)
                let projection = curve.project(point)
                let distanceToCurve = distance(point, projection.point)
                if distanceToCurve <= maximumDistance {
                    maximumDistance = distanceToCurve
                    bestSoFar = IndexedPathComponentLocation(elementIndex: elementIndex, t: projection.t)
                }
            }
            return true // visit children (if they exist)
        }
        if let bestSoFar = bestSoFar {
            return (point: self.point(at: bestSoFar), location: bestSoFar)
        }
        return nil
    }

    func project(_ point: Point) -> (point: Point, location: IndexedPathComponentLocation) {
        guard let result = searchForClosestLocation(to: point, maximumDistance: .infinity, requireBest: true) else {
            assertionFailure("expected non-empty result")
            return (point: startingPoint, startingIndexedLocation)
        }
        return result
    }

    func pointIsWithinDistanceOfBoundary(_ point: Point, distance: Double) -> Bool {
        return searchForClosestLocation(to: point, maximumDistance: distance, requireBest: false) != nil
    }
}

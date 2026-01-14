//
//  PathComponent.swift
//  BezierKit
//
//  Created by Holmes Futrell on 11/23/16.
//  Copyright © 2016 Holmes Futrell. All rights reserved.
//

import Foundation

public struct PathComponent: Hashable, Reversible, Transformable {
    private let offsets: [Int]
    public let points: [Point]
    public let orders: [Int]

    public var curves: [BezierCurve] { // in most cases use element(at:)
        return (0 ..< numberOfElements).map {
            self.element(at: $0)
        }
    }

    let bvh: BoundingBoxHierarchy

    public let boundingBoxOfPath: BoundingBox
    public let hash: Int
    public let length: Double

    public var boundingBox: BoundingBox {
        bvh.boundingBox
    }

    public var numberOfElements: Int {
        return orders.count
    }

    public var startingPoint: Point {
        return points[0]
    }

    public var endingPoint: Point {
        return points.last!
    }

    public var startingIndexedLocation: IndexedPathComponentLocation {
        return IndexedPathComponentLocation(elementIndex: 0, t: 0.0)
    }

    public var endingIndexedLocation: IndexedPathComponentLocation {
        return IndexedPathComponentLocation(elementIndex: numberOfElements - 1, t: 1.0)
    }

    /// if the path component represents a single point
    public var isPoint: Bool {
        return points.count == 1
    }

    public func element(at index: Int) -> BezierCurve {
        assert(index >= 0 && index < numberOfElements)
        let order = orders[index]
        if order == 3 {
            return cubic(at: index)
        } else if order == 2 {
            return quadratic(at: index)
        } else if order == 1 {
            return line(at: index)
        } else {
            // TODO: add Point:BezierCurve
            // for now just return a degenerate line
            let p = points[offsets[index]]
            return LineSegment(p0: p, p1: p)
        }
    }

    public func startingPointForElement(at index: Int) -> Point {
        return points[offsets[index]]
    }

    public func endingPointForElement(at index: Int) -> Point {
        return points[offsets[index] + orders[index]]
    }

    func cubic(at index: Int) -> CubicCurve {
        assert(order(at: index) == 3)
        let offset = offsets[index]
        return points.withUnsafeBufferPointer { p in
            CubicCurve(p0: p[offset], p1: p[offset + 1], p2: p[offset + 2], p3: p[offset + 3])
        }
    }

    func quadratic(at index: Int) -> QuadraticCurve {
        assert(order(at: index) == 2)
        let offset = offsets[index]
        return points.withUnsafeBufferPointer { p in
            QuadraticCurve(p0: p[offset], p1: p[offset + 1], p2: p[offset + 2])
        }
    }

    func line(at index: Int) -> LineSegment {
        assert(order(at: index) == 1)
        let offset = offsets[index]
        return points.withUnsafeBufferPointer { p in
            LineSegment(p0: p[offset], p1: p[offset + 1])
        }
    }

    func order(at index: Int) -> Int {
        return orders[index]
    }

    public init(points: [Point], orders: [Int]) {
        // TODO: I don't like that this constructor is exposed, but for certain performance critical things you need it
        precondition(orders.isEmpty == false, "Path components are by definition non-empty.")

        let expectedPointsCount = orders.reduce(1, +)
        assert(points.count == expectedPointsCount)

        var cursor = 0
        var hasher = Hasher()
        var offsets: [Int] = []
        var totalLength: Double = 0
        var boxes: [BoundingBox] = []
        var bboxOfPath = BoundingBox.empty

        offsets.reserveCapacity(orders.count)
        boxes.reserveCapacity(orders.count)

        func hashAndUnionToBox(_ point: Point) {
            hasher.combine(point.x)
            hasher.combine(point.y)
            bboxOfPath.union(point)
        }

        hashAndUnionToBox(points[0])
        for order in orders {
            hasher.combine(order)
            offsets.append(cursor)

            switch order {
            case 3:
                let curve = CubicCurve(p0: points[cursor], p1: points[cursor + 1], p2: points[cursor + 2], p3: points[cursor + 3])
                hashAndUnionToBox(points[cursor + 1])
                hashAndUnionToBox(points[cursor + 2])
                hashAndUnionToBox(points[cursor + 3])
                totalLength += curve.length()
                boxes.append(curve.boundingBox)
            case 2:
                let curve = QuadraticCurve(p0: points[cursor], p1: points[cursor + 1], p2: points[cursor + 2])
                hashAndUnionToBox(points[cursor + 1])
                hashAndUnionToBox(points[cursor + 2])
                totalLength += curve.length()
                boxes.append(curve.boundingBox)
            case 1:
                let curve = LineSegment(p0: points[cursor], p1: points[cursor + 1])
                hashAndUnionToBox(points[cursor + 1])
                totalLength += curve.length()
                boxes.append(curve.boundingBox)
            case 0:
                boxes.append(BoundingBox(p1: points[cursor], p2: points[cursor]))
            default:
                assertionFailure("unexpected curve order \(order). Expected between 0 (point) and 3 (cubic curve).")
            }

            cursor += order
        }

        // cursor is now sum(orders). Ensure we consumed the expected number of points.
        assert(cursor + 1 == points.count)

        self.points = points
        self.orders = orders
        self.offsets = offsets
        bvh = BoundingBoxHierarchy(boxes: boxes)
        boundingBoxOfPath = bboxOfPath
        hash = hasher.finalize()
        length = totalLength
    }

    public init(curve: BezierCurve) {
        self.init(curves: [curve])
    }

    public init(curves: [BezierCurve]) {
        precondition(curves.isEmpty == false, "Path components are by definition non-empty.")

        var orders: [Int] = []
        var points: [Point] = []
        var pointsCount = 0
        orders.reserveCapacity(curves.count)
        for curve in curves {
            pointsCount += curve.order
            orders.append(curve.order)
        }

        points.reserveCapacity(pointsCount + 1)
        points.append(curves.first!.startingPoint)
        for curve in curves {
            assert(curve.startingPoint == points.last!, "curves are not contiguous.")
            points.append(contentsOf: curve.points[1...])
        }

        self = .init(points: points, orders: orders)
    }

    public var isClosed: Bool {
        return startingPoint == endingPoint
    }

    public func offset(distance d: Double) -> PathComponent? {
        var offsetCurves = curves.reduce([]) {
            $0 + $1.offset(distance: d)
        }
        guard offsetCurves.isEmpty == false else { return nil }
        // force the set of curves to be contiguous
        for i in 0 ..< offsetCurves.count - 1 {
            let start = offsetCurves[i + 1].startingPoint
            let end = offsetCurves[i].endingPoint
            let average = Utils.linearInterpolate(start, end, 0.5)
            offsetCurves[i].endingPoint = average
            offsetCurves[i + 1].startingPoint = average
        }
        // we've touched everything but offsetCurves[0].startingPoint and offsetCurves[count-1].endingPoint
        // if we are a closed componenet, keep the offset component closed as well
        if isClosed {
            let start = offsetCurves[0].startingPoint
            let end = offsetCurves[offsetCurves.count - 1].endingPoint
            let average = Utils.linearInterpolate(start, end, 0.5)
            offsetCurves[0].startingPoint = average
            offsetCurves[offsetCurves.count - 1].endingPoint = average
        }
        return PathComponent(curves: offsetCurves)
    }

    private static func intersectionBetween<U>(_ curve: U, _ i2: Int, _ p2: PathComponent, accuracy: Double) -> [Intersection] where U: NonlinearBezierCurve {
        switch p2.order(at: i2) {
        case 0:
            return []
        case 1:
            return helperIntersectsCurveLine(curve, p2.line(at: i2))
        case 2:
            return helperIntersectsCurveCurve(Subcurve(curve: curve), Subcurve(curve: p2.quadratic(at: i2)), accuracy: accuracy)
        case 3:
            return helperIntersectsCurveCurve(Subcurve(curve: curve), Subcurve(curve: p2.cubic(at: i2)), accuracy: accuracy)
        default:
            fatalError("unsupported")
        }
    }

    private static func intersectionsBetweenElementAndLine(_ index: Int, _ line: LineSegment, _ component: PathComponent, reversed: Bool = false) -> [Intersection] {
        switch component.order(at: index) {
        case 0:
            return []
        case 1:
            let element = component.line(at: index)
            return reversed ? line.intersections(with: component.line(at: index)) : element.intersections(with: line)
        case 2:
            return helperIntersectsCurveLine(component.quadratic(at: index), line, reversed: reversed)
        case 3:
            return helperIntersectsCurveLine(component.cubic(at: index), line, reversed: reversed)
        default:
            fatalError("unsupported")
        }
    }

    private static func intersectionsBetweenElements(_ i1: Int, _ i2: Int, _ p1: PathComponent, _ p2: PathComponent, accuracy: Double) -> [Intersection] {
        switch p1.order(at: i1) {
        case 0:
            return []
        case 1:
            return PathComponent.intersectionsBetweenElementAndLine(i2, p1.line(at: i1), p2, reversed: true)
        case 2:
            return PathComponent.intersectionBetween(p1.quadratic(at: i1), i2, p2, accuracy: accuracy)
        case 3:
            return PathComponent.intersectionBetween(p1.cubic(at: i1), i2, p2, accuracy: accuracy)
        default:
            fatalError("unsupported")
        }
    }

    public func intersections(with other: PathComponent, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> [PathComponentIntersection] {
        var intersections: [PathComponentIntersection] = []
        let isClosed1 = isClosed
        let isClosed2 = other.isClosed
        bvh.enumerateIntersections(with: other.bvh) { i1, i2 in
            let elementIntersections = PathComponent.intersectionsBetweenElements(i1, i2, self, other, accuracy: accuracy)
            let pathComponentIntersections = elementIntersections.compactMap { (i: Intersection) -> PathComponentIntersection? in
                let i1 = IndexedPathComponentLocation(elementIndex: i1, t: i.t1)
                let i2 = IndexedPathComponentLocation(elementIndex: i2, t: i.t2)
                if i1.t == 0.0, isClosed1 || i1.elementIndex > 0 {
                    // handle this intersection instead at i1.elementIndex-1 w/ t=1
                    return nil
                }
                if i2.t == 0.0, isClosed2 || i2.elementIndex > 0 {
                    // handle this intersection instead at i2.elementIndex-1 w/ t=1
                    return nil
                }
                return PathComponentIntersection(indexedComponentLocation1: i1, indexedComponentLocation2: i2)
            }
            intersections += pathComponentIntersections
        }
        return intersections
    }

    private func neighborsIntersectOnlyTrivially(_ i1: Int, _ i2: Int) -> Bool {
        let b1 = bvh.boundingBox(forElementIndex: i1)
        let b2 = bvh.boundingBox(forElementIndex: i2)
        guard b1.intersection(b2).area == 0 else {
            return false
        }
        let numPoints = order(at: i2) + 1
        let offset = offsets[i2]
        for i in 1 ..< numPoints {
            if b1.contains(points[offset + i]) {
                return false
            }
        }
        return true
    }

    public func selfIntersections(accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> [PathComponentIntersection] {
        var intersections: [PathComponentIntersection] = []
        let isClosed = self.isClosed
        bvh.enumerateSelfIntersections { i1, i2 in
            var elementIntersections: [Intersection] = []
            if i1 == i2 {
                // we are intersecting a path element against itself (only possible with cubic or higher order)
                if self.order(at: i1) == 3 {
                    elementIntersections = self.cubic(at: i1).selfIntersections
                }
            } else if i1 < i2 {
                // we are intersecting two distinct path elements
                let areNeighbors = (i1 == i2 - 1) || (isClosed && i1 == 0 && i2 == self.numberOfElements - 1)
                if areNeighbors, neighborsIntersectOnlyTrivially(i1, i2) {
                    // optimize the very common case of element i intersecting i+1 at its endpoint
                    elementIntersections = []
                } else {
                    elementIntersections = PathComponent.intersectionsBetweenElements(i1, i2, self, self, accuracy: accuracy).filter {
                        if i1 == i2 - 1, $0.t1 == 1.0, $0.t2 == 0.0 {
                            return false // exclude intersections of i and i+1 at t=1
                        }
                        if i1 == 0, i2 == self.numberOfElements - 1, $0.t1 == 0.0, $0.t2 == 1.0 {
                            assert(self.isClosed) // how else can that happen?
                            return false // exclude intersections of endpoint and startpoint
                        }
                        if $0.t1 == 0.0, i1 > 0 || isClosed {
                            // handle the intersections instead at i1-1, t=1
                            return false
                        }
                        if $0.t2 == 0.0 {
                            // handle the intersections instead at i2-1, t=1 (we know i2 > 0 because i2 > i1)
                            return false
                        }
                        return true
                    }
                }
            }
            intersections += elementIntersections.map {
                PathComponentIntersection(indexedComponentLocation1: IndexedPathComponentLocation(elementIndex: i1, t: $0.t1),
                                          indexedComponentLocation2: IndexedPathComponentLocation(elementIndex: i2, t: $0.t2))
            }
        }
        return intersections
    }

    // MARK: -

    private func assertLocationHasValidElementIndex(_ location: IndexedPathComponentLocation) {
        assert(location.elementIndex >= 0 && location.elementIndex < numberOfElements)
    }

    private func assertionFailureBadCurveOrder(_ order: Int) {
        assertionFailure("unexpected curve order \(order). Expected between 0 (point) and 3 (cubic curve).")
    }

    public func point(at location: IndexedPathComponentLocation) -> Point {
        assertLocationHasValidElementIndex(location)
        let elementIndex = location.elementIndex
        let t = location.t
        let order = orders[elementIndex]
        switch orders[elementIndex] {
        case 3:
            return cubic(at: elementIndex).point(at: t)
        case 2:
            return quadratic(at: elementIndex).point(at: t)
        case 1:
            return line(at: elementIndex).point(at: t)
        case 0:
            return points[offsets[elementIndex]]
        default:
            assertionFailureBadCurveOrder(order)
            return points[offsets[elementIndex]]
        }
    }

    public func derivative(at location: IndexedPathComponentLocation) -> Point {
        assertLocationHasValidElementIndex(location)
        let elementIndex = location.elementIndex
        let t = location.t
        let order = orders[elementIndex]
        switch order {
        case 3:
            return cubic(at: elementIndex).derivative(at: t)
        case 2:
            return quadratic(at: elementIndex).derivative(at: t)
        case 1:
            return line(at: elementIndex).derivative(at: t)
        case 0:
            return .zero
        default:
            assertionFailureBadCurveOrder(order)
            return .zero
        }
    }

    public func normal(at location: IndexedPathComponentLocation) -> Point {
        assertLocationHasValidElementIndex(location)
        let elementIndex = location.elementIndex
        let t = location.t
        let order = orders[elementIndex]
        switch order {
        case 3:
            return cubic(at: elementIndex).normal(at: t)
        case 2:
            return quadratic(at: elementIndex).normal(at: t)
        case 1:
            return line(at: elementIndex).normal(at: t)
        case 0:
            return Point(x: Double.nan, y: Double.nan)
        default:
            assertionFailureBadCurveOrder(order)
            return Point(x: Double.nan, y: Double.nan)
        }
    }

    public func contains(_ point: Point, using rule: PathFillRule = .winding) -> Bool {
        let windingCount = self.windingCount(at: point)
        return windingCountImpliesContainment(windingCount, using: rule)
    }

    public func enumeratePoints(includeControlPoints: Bool, using block: (Point) -> Void) {
        if includeControlPoints {
            for p in points {
                block(p)
            }
        } else {
            for o in offsets {
                block(points[o])
            }
            if points.count > 1 {
                block(points.last!)
            }
        }
    }

    public func split(standardizedRange range: PathComponentRange, bias: PathComponentBias) -> Self {
        assert(range.isStandardized)
        guard !isPoint else { return self }

        func splitElement(at index: Int, start: Double, end: Double, includeStart: Bool, includeEnd: Bool) -> (points: [Point], order: Int) {
            assert(includeStart || includeEnd)
            let element = element(at: index).split(from: start, to: end)
            let startIndex = includeStart ? 0 : 1
            let endIndex = includeEnd ? element.order : element.order - 1
            return (
                points: Array(element.points[startIndex ... endIndex]),
                order: orders[index]
            )
        }

        func splitInner(start: IndexedPathComponentLocation, end: IndexedPathComponentLocation) -> (points: [Point], orders: [Int]) {
            guard start.elementIndex != end.elementIndex else {
                // we just need to go from start.t to end.t
                let (points, order) = splitElement(at: start.elementIndex, start: start.t, end: end.t, includeStart: true, includeEnd: true)
                return (points, [order])
            }
            var resultPoints: [Point] = []
            var resultOrders: [Int] = []

            // if end.t = 1, append from start.elementIndex+1 through end.elementIndex, otherwise to end.elementIndex
            let lastElementIndex = end.t != 1.0 ? (end.elementIndex - 1) : end.elementIndex
            let firstElementIndex = start.t != 0.0 ? (start.elementIndex + 1) : start.elementIndex

            // if needed, append start.elementIndex from t=start.t to t=1
            if firstElementIndex != start.elementIndex {
                let (points, order) = splitElement(at: start.elementIndex, start: start.t, end: 1.0, includeStart: true, includeEnd: false)
                resultPoints.append(contentsOf: points)
                resultOrders.append(order)
            }
            // if there exist full elements to copy, use the fast path to get them all in one fell swoop
            let hasFullElements = firstElementIndex <= lastElementIndex
            if hasFullElements {
                let points = points[offsets[firstElementIndex] ... offsets[lastElementIndex] + orders[lastElementIndex]]
                let orders = orders[firstElementIndex ... lastElementIndex]
                resultPoints.append(contentsOf: points)
                resultOrders.append(contentsOf: orders)
            }
            // if needed, append from end.elementIndex from t=0, to t=end.t
            if lastElementIndex != end.elementIndex {
                let (points, order) = splitElement(at: end.elementIndex, start: 0.0, end: end.t, includeStart: !hasFullElements, includeEnd: true)
                resultPoints.append(contentsOf: points)
                resultOrders.append(order)
            }
            return (points: resultPoints, orders: resultOrders)
        }

        func splitOuter(start: IndexedPathComponentLocation, end: IndexedPathComponentLocation) -> (points: [Point], orders: [Int]) {
            var resultPoints: [Point] = []
            var resultOrders: [Int] = []

            // if end.t = 0, append from end.elementIndex+1 through start.elementIndex-1, otherwise from end.elementIndex
            let lastElementIndex = end.t != 0.0 ? (end.elementIndex + 1) : end.elementIndex
            let firstElementIndex = start.t != 1.0 ? (start.elementIndex - 1) : start.elementIndex

            // if there exist full elements to copy, use the fast path to get them all in one fell swoop
            let hasFullElementsL = firstElementIndex > 0
            let hasFullElementsR = lastElementIndex < numberOfElements

            if lastElementIndex != end.elementIndex { // right splitted curve
                let includeEndPoint = !(hasFullElementsR || hasFullElementsL)
                let (points, order) = splitElement(at: end.elementIndex, start: end.t, end: 1.0, includeStart: true, includeEnd: includeEndPoint)
                resultPoints.append(contentsOf: points)
                resultOrders.append(order)
            }
            if hasFullElementsR {
                let points = points[offsets[lastElementIndex] ... offsets[numberOfElements - 1] + orders[numberOfElements - 1]]
                let orders = orders[lastElementIndex ..< numberOfElements]
                resultPoints.append(contentsOf: points)
                resultOrders.append(contentsOf: orders)
            }
            if hasFullElementsL {
                let points = points[0 ..< offsets[firstElementIndex] + orders[firstElementIndex] + (hasFullElementsR ? 0 : 1)]
                let orders = orders[0 ... firstElementIndex]
                resultPoints.append(contentsOf: points)
                resultOrders.append(contentsOf: orders)
            }
            if firstElementIndex != start.elementIndex { // left splitted curve
                let (points, order) = splitElement(at: start.elementIndex, start: 0.0, end: start.t, includeStart: false, includeEnd: true)
                resultPoints.append(contentsOf: points)
                resultOrders.append(order)
            }
            return (points: resultPoints, orders: resultOrders)
        }

        switch bias {
        case .inner:
            let (resultPoints, resultOrders) = splitInner(
                start: range.start,
                end: range.end
            )
            return Self(points: resultPoints, orders: resultOrders)

        case .outer:
            let (resultPoints, resultOrders) = splitOuter(
                start: range.start,
                end: range.end
            )
            return Self(points: resultPoints, orders: resultOrders)
        }
    }

    public func split(range: PathComponentRange, bias: PathComponentBias) -> Self {
        let reverse = range.end < range.start
        let result = split(standardizedRange: range.standardized, bias: bias)
        return reverse ? result.reversed() : result
    }

    public func split(from start: IndexedPathComponentLocation, to end: IndexedPathComponentLocation, bias: PathComponentBias = .inner) -> Self {
        return split(range: PathComponentRange(from: start, to: end), bias: bias)
    }

    public func reversed() -> Self {
        return Self(points: points.reversed(), orders: orders.reversed())
    }

    public func copy(using t: AffineTransform) -> Self {
        return Self(points: points.map { $0.applying(t) }, orders: orders)
    }
}

public extension PathComponent {
    static func == (lhs: PathComponent, rhs: PathComponent) -> Bool {
        return lhs.orders == rhs.orders && lhs.points == rhs.points
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }
}

private extension PathComponent {
    static func computeBoundingBoxOfPathAndHash(points: [Point], orders: [Int]) -> (boundingBoxOfPath: BoundingBox, hash: Int) {
        var hasher = Hasher()
        orders.withUnsafeBytes {
            hasher.combine(bytes: $0)
        }
        var boundingBoxOfPath = BoundingBox.empty
        points.withUnsafeBufferPointer { buffer in
            for point in buffer {
                boundingBoxOfPath.union(point)
                hasher.combine(point.x)
                hasher.combine(point.y)
            }
        }
        return (boundingBoxOfPath, hasher.finalize())
    }

    static func computeElementBoundingBoxes(points: [Point], orders: [Int], offsets: [Int]) -> [BoundingBox] {
        assert(orders.count == offsets.count)
        return points.withUnsafeBufferPointer { p in
            [BoundingBox](unsafeUninitializedCapacity: orders.count) { buffer, initializedCount in
                for elementIndex in 0 ..< orders.count {
                    let order = orders[elementIndex]
                    let offset = offsets[elementIndex]
                    let box: BoundingBox
                    switch order {
                    case 3:
                        box = CubicCurve(
                            p0: p[offset],
                            p1: p[offset + 1],
                            p2: p[offset + 2],
                            p3: p[offset + 3]
                        ).boundingBox
                    case 2:
                        box = QuadraticCurve(
                            p0: p[offset],
                            p1: p[offset + 1],
                            p2: p[offset + 2]
                        ).boundingBox
                    case 1:
                        box = LineSegment(
                            p0: p[offset],
                            p1: p[offset + 1]
                        ).boundingBox
                    case 0:
                        let pt = p[offset]
                        box = LineSegment(p0: pt, p1: pt).boundingBox
                    default:
                        fatalError("unexpected curve order \(order). Expected between 0 (point) and 3 (cubic curve).")
                    }
                    buffer[elementIndex] = box
                }
                initializedCount = orders.count
            }
        }
    }
}

public struct IndexedPathComponentLocation: Equatable, Comparable {
    public let elementIndex: Int
    public let t: Double
    public init(elementIndex: Int, t: Double) {
        self.elementIndex = elementIndex
        self.t = t
    }

    public static func < (lhs: IndexedPathComponentLocation, rhs: IndexedPathComponentLocation) -> Bool {
        if lhs.elementIndex < rhs.elementIndex {
            return true
        } else if lhs.elementIndex > rhs.elementIndex {
            return false
        }
        return lhs.t < rhs.t
    }
}

public struct PathComponentIntersection {
    public let indexedComponentLocation1, indexedComponentLocation2: IndexedPathComponentLocation
}

public struct PathComponentRange: Equatable {
    public var start: IndexedPathComponentLocation
    public var end: IndexedPathComponentLocation
    public init(from start: IndexedPathComponentLocation, to end: IndexedPathComponentLocation) {
        self.start = start
        self.end = end
    }

    var isStandardized: Bool {
        return self == standardized
    }

    /// the range standardized so that end >= start and adjusted to avoid possible degeneracies when splitting components
    public var standardized: PathComponentRange {
        var start = self.start
        var end = self.end
        if end < start {
            swap(&start, &end)
        }
        if start.elementIndex < end.elementIndex {
            if start.t == 1.0 {
                let candidate = IndexedPathComponentLocation(elementIndex: start.elementIndex + 1, t: 0.0)
                if candidate <= end {
                    start = candidate
                }
            }
            if end.t == 0.0 {
                let candidate = IndexedPathComponentLocation(elementIndex: end.elementIndex - 1, t: 1.0)
                if candidate >= start {
                    end = candidate
                }
            }
        }
        return PathComponentRange(from: start, to: end)
    }
}

public enum PathComponentBias: Equatable {
    case inner
    case outer
}

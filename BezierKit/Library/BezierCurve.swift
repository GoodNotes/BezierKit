//
//  BezierCurve.swift
//  BezierKit
//
//  Created by Holmes Futrell on 2/19/17.
//  Copyright © 2017 Holmes Futrell. All rights reserved.
//

public struct Subcurve<CurveType> where CurveType: BezierCurve {
    public let t1: Double
    public let t2: Double
    public let curve: CurveType

    var canSplit: Bool {
        let mid = 0.5 * (t1 + t2)
        return mid > t1 && mid < t2
    }

    init(curve: CurveType) {
        t1 = 0.0
        t2 = 1.0
        self.curve = curve
    }

    init(t1: Double, t2: Double, curve: CurveType) {
        self.t1 = t1
        self.t2 = t2
        self.curve = curve
    }

    func split(from t1: Double, to t2: Double) -> Subcurve<CurveType> {
        let curve: CurveType = self.curve.split(from: t1, to: t2)
        return Subcurve<CurveType>(t1: Utils.map(t1, 0, 1, self.t1, self.t2),
                                   t2: Utils.map(t2, 0, 1, self.t1, self.t2),
                                   curve: curve)
    }

    func split(at t: Double) -> (left: Subcurve<CurveType>, right: Subcurve<CurveType>) {
        let (left, right) = curve.split(at: t)
        let t1 = self.t1
        let t2 = self.t2
        let tSplit = Utils.map(t, 0, 1, t1, t2)
        let subcurveLeft = Subcurve<CurveType>(t1: t1, t2: tSplit, curve: left)
        let subcurveRight = Subcurve<CurveType>(t1: tSplit, t2: t2, curve: right)
        return (left: subcurveLeft, right: subcurveRight)
    }
}

extension Subcurve: Equatable where CurveType: Equatable {
    // extension exists for automatic Equatable synthesis
}

// MARK: -

public extension BezierCurve {
    /*
     Calculates the length of this Bezier curve. Length is calculated using numerical approximation, specifically the Legendre-Gauss quadrature algorithm.
     */
    func length() -> Double {
        return Utils.length { (_ t: Double) in self.derivative(at: t) }
    }

    // MARK: -

    func hull(_ t: Double) -> [Point] {
        return Utils.hull(points, t)
    }

    func lookupTable(steps: Int = 100) -> [Point] {
        assert(steps >= 0)
        return (0 ... steps).map {
            let t = Double($0) / Double(steps)
            return self.point(at: t)
        }
    }

    // MARK: -

    /*
     Reduces a curve to a collection of "simple" subcurves, where a simpleness is defined as having all control points on the same side of the baseline (cubics having the additional constraint that the control-to-end-point lines may not cross), and an angle between the end point normals no greater than 60 degrees.

     The main reason this function exists is to make it possible to scale curves. As mentioned in the offset function, curves cannot be offset without cheating, and the cheating is implemented in this function. The array of simple curves that this function yields can safely be scaled.

     */

    func reduce() -> [Subcurve<Self>] {
        let step: Double = BezierKit.reduceStepSize
        var extrema: [Double] = []
        self.extrema().all.forEach {
            if $0 < step {
                return // filter out extreme points very close to 0.0
            } else if (1.0 - $0) < step {
                return // filter out extreme points very close to 1.0
            } else if let last = extrema.last, $0 - last < step {
                return
            }
            return extrema.append($0)
        }
        // aritifically add 0.0 and 1.0 to our extreme points
        extrema.insert(0.0, at: 0)
        extrema.append(1.0)

        // first pass: split on extrema
        let pass1: [Subcurve<Self>] = (0 ..< extrema.count - 1).map {
            let t1 = extrema[$0]
            let t2 = extrema[$0 + 1]
            let curve = self.split(from: t1, to: t2)
            return Subcurve(t1: t1, t2: t2, curve: curve)
        }

        func bisectionMethod(min: Double, max: Double, tolerance: Double, callback: (_ value: Double) -> Bool) -> Double {
            var lb = min // lower bound (callback(x <= lb) should return true
            var ub = max // upper bound (callback(x >= ub) should return false
            while (ub - lb) > tolerance {
                let val = 0.5 * (lb + ub)
                if callback(val) {
                    lb = val
                } else {
                    ub = val
                }
            }
            return lb
        }

        // second pass: further reduce these segments to simple segments
        var pass2: [Subcurve<Self>] = []
        pass2.reserveCapacity(pass1.count)
        for p1 in pass1 {
            let adjustedStep = step / (p1.t2 - p1.t1)
            var t1 = 0.0
            while t1 < 1.0 {
                let fullSegment = p1.split(from: t1, to: 1.0)
                if (1.0 - t1) <= adjustedStep || fullSegment.curve.simple {
                    // if the step is small or the full segment is simple, use it
                    pass2.append(fullSegment)
                    t1 = 1.0
                } else {
                    // otherwise use bisection method to find a suitable step size
                    let t2 = bisectionMethod(min: t1 + adjustedStep, max: 1.0, tolerance: adjustedStep) {
                        p1.split(from: t1, to: $0).curve.simple
                    }
                    let partialSegment = p1.split(from: t1, to: t2)
                    pass2.append(partialSegment)
                    t1 = t2
                }
            }
        }
        return pass2
    }

    // MARK: -

    /// Scales a curve with respect to the intersection between the end point normals. Note that this will only work if that intersection point exists, which is only guaranteed for simple segments.
    /// - Parameter distance: desired distance the resulting curve should fall from the original (in the direction of its normals).
    func scale(distance: Double) -> Self? {
        let order = self.order
        assert(order < 4, "only works with cubic or lower order")
        guard order > 0 else { return self } // points cannot be scaled
        let points = self.points

        let n1 = normal(at: 0)
        let n2 = normal(at: 1)
        guard n1.x.isFinite, n1.y.isFinite, n2.x.isFinite, n2.y.isFinite else { return nil }

        let origin = Utils.linesIntersection(startingPoint, startingPoint + n1, endingPoint, endingPoint - n2)
        func scaledPoint(index: Int) -> Point {
            let referencePointIsStart = (index < 2 && order > 1) || (index == 0 && order == 1)
            let referenceT: Double = referencePointIsStart ? 0.0 : 1.0
            let referenceIndex = referencePointIsStart ? 0 : self.order
            let referencePoint = offset(t: referenceT, distance: distance)
            switch index {
            case 0, self.order:
                return referencePoint
            default:
                let tangent = normal(at: referenceT).perpendicular
                if let origin = origin, let intersection = Utils.linesIntersection(referencePoint, referencePoint + tangent, origin, points[index]) {
                    return intersection
                } else {
                    // no origin to scale control points through, just use start and end points as a reference
                    return referencePoint + (points[index] - points[referenceIndex])
                }
            }
        }
        let scaledPoints = (0 ..< self.points.count).map(scaledPoint)
        return type(of: self).init(points: scaledPoints)
    }

    // MARK: -

    func offset(distance d: Double) -> [BezierCurve] {
        // for non-linear curves we need to create a set of curves
        var result: [BezierCurve] = reduce().compactMap { $0.curve.scale(distance: d) }
        ensureContinuous(&result, isClosed: false)
        return result
    }

    func offset(t: Double, distance: Double) -> Point {
        return point(at: t) + distance * normal(at: t)
    }

    // MARK: - outlines

    func outline(distance d1: Double) -> PathComponent {
        return internalOutline(d1: d1, d2: d1)
    }

    func outline(distanceAlongNormal d1: Double, distanceOppositeNormal d2: Double) -> PathComponent {
        return internalOutline(d1: d1, d2: d2)
    }

    private func ensureContinuous(_ curves: inout [BezierCurve], isClosed: Bool) {
        BezierCurveType.ensureContinuous(&curves, isClosed: isClosed)
    }

    private func internalOutline(d1: Double, d2: Double) -> PathComponent {
        let reduced = reduce()
        let length = reduced.count
        var forwardCurves: [BezierCurve] = reduced.compactMap { $0.curve.scale(distance: d1) }
        var backCurves: [BezierCurve] = reduced.compactMap { $0.curve.scale(distance: -d2) }
        ensureContinuous(&forwardCurves, isClosed: false)
        ensureContinuous(&backCurves, isClosed: false)
        // reverse the "return" outline
        backCurves = backCurves.reversed().map { $0.reversed() }
        // form the endcaps as lines
        let forwardStart = forwardCurves[0].points[0]
        let forwardEnd = forwardCurves[length - 1].points[forwardCurves[length - 1].points.count - 1]
        let backStart = backCurves[length - 1].points[backCurves[length - 1].points.count - 1]
        let backEnd = backCurves[0].points[0]
        let lineStart = LineSegment(p0: backStart, p1: forwardStart)
        let lineEnd = LineSegment(p0: forwardEnd, p1: backEnd)
        let segments = [lineStart] + forwardCurves + [lineEnd] + backCurves
        return PathComponent(curves: segments)
    }

    // MARK: shapes

    func outlineShapes(distance d1: Double, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> [Shape] {
        return outlineShapes(distanceAlongNormal: d1, distanceOppositeNormal: d1, accuracy: accuracy)
    }

    func outlineShapes(distanceAlongNormal d1: Double, distanceOppositeNormal d2: Double, accuracy _: Double = BezierKit.defaultIntersectionAccuracy) -> [Shape] {
        let outline = self.outline(distanceAlongNormal: d1, distanceOppositeNormal: d2)
        var shapes: [Shape] = []
        let len = outline.numberOfElements
        for i in 1 ..< len / 2 {
            let shape = Shape(outline.element(at: i), outline.element(at: len - i), i > 1, i < len / 2 - 1)
            shapes.append(shape)
        }
        return shapes
    }
}

enum BezierCurveType {
    static func ensureContinuous(_ curves: inout [BezierCurve], isClosed: Bool) {
        for i in 0 ..< curves.count {
            if i > 0 {
                curves[i].startingPoint = curves[i - 1].endingPoint
            }
            if i < curves.count - 1 {
                curves[i].endingPoint = 0.5 * (curves[i].endingPoint + curves[i + 1].startingPoint)
            }
        }
        if isClosed, curves.count > 1 {
            curves[curves.count - 1].endingPoint = curves[0].startingPoint
        }
    }
}

public extension Array where Element == BezierCurve {
    func ensureContinuous(isClosed: Bool) -> [BezierCurve] {
        var result = Array(self)
        BezierCurveType.ensureContinuous(&result, isClosed: isClosed)
        return result
    }
}

public let defaultIntersectionAccuracy = Double(0.5)
let reduceStepSize: Double = 0.01

public func == (left: BezierCurve, right: BezierCurve) -> Bool {
    return left.points == right.points
}

public protocol BoundingBoxProtocol {
    var boundingBox: BoundingBox { get }
}

public protocol Transformable {
    func copy(using: AffineTransform) -> Self
}

public protocol Reversible {
    func reversed() -> Self
}

public protocol BezierCurve: BoundingBoxProtocol, Transformable, Reversible {
    var simple: Bool { get }
    var points: [Point] { get }
    var startingPoint: Point { get set }
    var endingPoint: Point { get set }
    var order: Int { get }
    init(points: [Point])
    func point(at t: Double) -> Point
    func derivative(at t: Double) -> Point
    func normal(at t: Double) -> Point
    func split(from t1: Double, to t2: Double) -> Self
    func split(at t: Double) -> (left: Self, right: Self)
    func length() -> Double
    func extrema() -> (x: [Double], y: [Double], all: [Double])
    func lookupTable(steps: Int) -> [Point]
    func project(_ point: Point) -> (point: Point, t: Double)
    // intersection routines
    var selfIntersects: Bool { get }
    var selfIntersections: [Intersection] { get }
    func intersects(_ line: LineSegment) -> Bool
    func intersects(_ curve: BezierCurve, accuracy: Double) -> Bool
    func intersections(with line: LineSegment) -> [Intersection]
    func intersections(with curve: BezierCurve, accuracy: Double) -> [Intersection]
}

protocol NonlinearBezierCurve: BezierCurve, ComponentPolynomials, Implicitizeable {
    // intentionally empty, just declare conformance if you're not a line
}

public protocol Flatness: BezierCurve {
    // the flatness of a curve is defined as the square of the maximum distance it is from a line connecting its endpoints https://jeremykun.com/2013/05/11/bezier-curves-and-picasso/
    var flatnessSquared: Double { get }
    var flatness: Double { get }
}

public extension Flatness {
    var flatness: Double {
        return BezierMath.sqrt(flatnessSquared)
    }
}

//
//  QuadraticCurve.swift
//  BezierKit
//
//  Created by Holmes Futrell on 3/3/17.
//  Copyright © 2017 Holmes Futrell. All rights reserved.
//

import Foundation

public struct QuadraticCurve: NonlinearBezierCurve, Equatable {
    public var p0, p1, p2: Point

    public init(points: [Point]) {
        precondition(points.count == 3)
        p0 = points[0]
        p1 = points[1]
        p2 = points[2]
    }

    public init(p0: Point, p1: Point, p2: Point) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
    }

    public init(lineSegment l: LineSegment) {
        self.init(p0: l.p0, p1: 0.5 * (l.p0 + l.p1), p2: l.p1)
    }

    var downgradedToLineSegment: (lineSegment: LineSegment, error: Double) {
        let line = LineSegment(p0: startingPoint, p1: endingPoint)
        let error = 0.5 * (p1 - line.point(at: 0.5)).length
        return (lineSegment: line, error: error)
    }

    public init(start: Point, end: Point, mid: Point, t: Double = 0.5) {
        // shortcuts, although they're really dumb
        if t == 0 {
            self.init(p0: mid, p1: mid, p2: end)
        } else if t == 1 {
            self.init(p0: start, p1: mid, p2: mid)
        } else {
            // real fitting.
            let abc = Utils.getABC(n: 2, S: start, B: mid, E: end, t: t)
            self.init(p0: start, p1: abc.A, p2: end)
        }
    }

    public var points: [Point] {
        return [p0, p1, p2]
    }

    public var startingPoint: Point {
        get {
            return p0
        }
        set(newValue) {
            p0 = newValue
        }
    }

    public var endingPoint: Point {
        get {
            return p2
        }
        set(newValue) {
            p2 = newValue
        }
    }

    public var order: Int {
        return 2
    }

    public var simple: Bool {
        guard p0 != p1 || p1 != p2 else { return true }
        let n1 = normal(at: 0)
        let n2 = normal(at: 1)
        let s = Utils.clamp(n1.dot(n2), -1.0, 1.0)
        let angle = Double(abs(acos(Double(s))))
        return angle < (Double.pi / 3.0)
    }

    public func normal(at t: Double) -> Point {
        var d = derivative(at: t)
        if d == Point.zero, t == 0.0 || t == 1.0 {
            if t == 0.0 {
                d = p2 - p1
            } else {
                d = p1 - p0
            }
        }
        return d.perpendicular.normalize()
    }

    public func derivative(at t: Double) -> Point {
        let mt: Double = 1 - t
        let k: Double = 2
        let p0 = k * (self.p1 - self.p0)
        let p1 = k * (p2 - self.p1)
        let a = mt
        let b = t
        return a * p0 + b * p1
    }

    public func split(from t1: Double, to t2: Double) -> QuadraticCurve {
        guard t1 != 0.0 || t2 != 1.0 else { return self }
        let k = (t2 - t1) / 2
        let p0 = point(at: t1)
        let p2 = point(at: t2)
        let p1 = (p0 + p2) / 2 + k / 2 * (derivative(at: t1) - derivative(at: t2))
        return QuadraticCurve(p0: p0, p1: p1, p2: p2)
    }

    public func split(at t: Double) -> (left: QuadraticCurve, right: QuadraticCurve) {
        // use "de Casteljau" iteration.
        let h0 = p0
        let h1 = p1
        let h2 = p2
        let h3 = Utils.linearInterpolate(h0, h1, t)
        let h4 = Utils.linearInterpolate(h1, h2, t)
        let h5 = Utils.linearInterpolate(h3, h4, t)

        let leftCurve = QuadraticCurve(p0: h0, p1: h3, p2: h5)
        let rightCurve = QuadraticCurve(p0: h5, p1: h4, p2: h2)

        return (left: leftCurve, right: rightCurve)
    }

    public func project(_ point: Point) -> (point: Point, t: Double) {
        func multiplyCoordinates(_ a: Point, _ b: Point) -> Point {
            return Point(x: a.x * b.x, y: a.y * b.y)
        }
        let q = copy(using: AffineTransform(translationX: -point.x, y: -point.y))
        // p0, p1, p2, p3 form the control points of a cubic Bezier curve
        // created by multiplying the curve with its derivative
        let qd0 = q.p1 - q.p0
        let qd1 = q.p2 - q.p1
        let p0 = 3 * multiplyCoordinates(q.p0, qd0)
        let p1 = multiplyCoordinates(q.p0, qd1) + 2 * multiplyCoordinates(q.p1, qd0)
        let p2 = multiplyCoordinates(q.p2, qd0) + 2 * multiplyCoordinates(q.p1, qd1)
        let p3 = 3 * multiplyCoordinates(q.p2, qd1)
        let lengthSquaredStart = q.startingPoint.lengthSquared
        let lengthSquaredEnd = q.endingPoint.lengthSquared
        var minimumT = 0.0
        var minimumDistanceSquared = lengthSquaredStart
        if lengthSquaredEnd < lengthSquaredStart {
            minimumT = 1.0
            minimumDistanceSquared = lengthSquaredEnd
        }
        // the roots represent the values at which the curve and its derivative are perpendicular
        // ie, the dot product of q and l is equal to zero
        Utils.droots(p0.x + p0.y, p1.x + p1.y, p2.x + p2.y, p3.x + p3.y) { (t: Double) in
            guard t > 0.0, t < 1.0 else { return }
            let point = q.point(at: t)
            let distanceSquared = point.lengthSquared
            if distanceSquared < minimumDistanceSquared {
                minimumDistanceSquared = distanceSquared
                minimumT = t
            }
        }
        return (point: self.point(at: minimumT), t: minimumT)
    }

    public var boundingBox: BoundingBox {
        let p0: Point = self.p0
        let p1: Point = self.p1
        let p2: Point = self.p2

        var mmin = Point.min(p0, p2)
        var mmax = Point.max(p0, p2)

        let d0: Point = p1 - p0
        let d1: Point = p2 - p1

        for d in 0 ..< Point.dimensions {
            Utils.droots(d0[d], d1[d]) { (t: Double) in
                guard t > 0.0, t < 1.0 else {
                    return
                }
                let value = self.point(at: t)[d]
                if value < mmin[d] {
                    mmin[d] = value
                } else if value > mmax[d] {
                    mmax[d] = value
                }
            }
        }
        return BoundingBox(min: mmin, max: mmax)
    }

    public func point(at t: Double) -> Point {
        if t == 0 {
            return p0
        } else if t == 1 {
            return p2
        }
        let mt = 1.0 - t
        let mt2: Double = mt * mt
        let t2: Double = t * t
        let a = mt2
        let b = mt * t * 2
        let c = t2
        // making the final sum one line of code makes XCode take forever to compiler! Hence the temporary variables.
        let temp1 = a * p0
        let temp2 = b * p1
        let temp3 = c * p2
        return temp1 + temp2 + temp3
    }
}

extension QuadraticCurve: Transformable {
    public func copy(using t: AffineTransform) -> QuadraticCurve {
        return QuadraticCurve(p0: p0.applying(t), p1: p1.applying(t), p2: p2.applying(t))
    }
}

extension QuadraticCurve: Reversible {
    public func reversed() -> QuadraticCurve {
        return QuadraticCurve(p0: p2, p1: p1, p2: p0)
    }
}

extension QuadraticCurve: Flatness {
    public var flatnessSquared: Double {
        let a: Point = 2.0 * p1 - p0 - p2
        return (1.0 / 16.0) * (a.x * a.x + a.y * a.y)
    }
}

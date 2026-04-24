//
//  LineSegment.swift
//  BezierKit
//
//  Created by Holmes Futrell on 5/14/17.
//  Copyright © 2017 Holmes Futrell. All rights reserved.
//

public struct LineSegment: BezierCurve, Equatable {
    public var p0, p1: Point

    public init(points: [Point]) {
        precondition(points.count == 2)
        p0 = points[0]
        p1 = points[1]
    }

    public init(p0: Point, p1: Point) {
        self.p0 = p0
        self.p1 = p1
    }

    public var points: [Point] {
        return [p0, p1]
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
            return p1
        }
        set(newValue) {
            p1 = newValue
        }
    }

    public var order: Int {
        return 1
    }

    public var simple: Bool {
        return true
    }

    public func derivative(at _: Double) -> Point {
        return p1 - p0
    }

    public func normal(at _: Double) -> Point {
        return (p1 - p0).perpendicular.normalize()
    }

    public func split(from t1: Double, to t2: Double) -> LineSegment {
        return LineSegment(p0: point(at: t1), p1: point(at: t2))
    }

    public func split(at t: Double) -> (left: LineSegment, right: LineSegment) {
        let p0 = self.p0
        let p1 = self.p1
        let mid = Utils.linearInterpolate(p0, p1, t)
        let left = LineSegment(p0: p0, p1: mid)
        let right = LineSegment(p0: mid, p1: p1)
        return (left: left, right: right)
    }

    public var boundingBox: BoundingBox {
        let p0: Point = self.p0
        let p1: Point = self.p1
        return BoundingBox(min: Point.min(p0, p1), max: Point.max(p0, p1))
    }

    public func point(at t: Double) -> Point {
        if t == 0 {
            return p0
        } else if t == 1 {
            return p1
        } else {
            return Utils.linearInterpolate(p0, p1, t)
        }
    }

    // -- MARK: - overrides

    public func length() -> Double {
        return (p1 - p0).length
    }

    public func extrema() -> (x: [Double], y: [Double], all: [Double]) {
        return (x: [], y: [], all: [])
    }

    public func project(_ point: Point) -> (point: Point, t: Double) {
        // optimized implementation for line segments can be directly computed
        // default project implementation is found in BezierCurve protocol extension
        let relativePoint = point - p0
        let delta = p1 - p0
        let t = Utils.clamp(relativePoint.dot(delta) / delta.dot(delta), 0.0, 1.0)
        return (point: self.point(at: t), t: t)
    }
}

extension LineSegment: Transformable {
    public func copy(using t: AffineTransform) -> LineSegment {
        return LineSegment(p0: p0.applying(t), p1: p1.applying(t))
    }
}

extension LineSegment: Reversible {
    public func reversed() -> LineSegment {
        return LineSegment(p0: p1, p1: p0)
    }
}

extension LineSegment: Flatness {
    public var flatnessSquared: Double { return 0.0 }
    public var flatness: Double { return 0.0 }
}

//
//  Types.swift
//  BezierKit
//
//  Created by Holmes Futrell on 11/3/16.
//  Copyright © 2016 Holmes Futrell. All rights reserved.
//

import Foundation

// MARK: - Geometry primitives (CoreGraphics-independent)

public struct Point: Hashable {
    public var x: Double
    public var y: Double

    @inlinable public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public extension Point {
    func applying(_ t: AffineTransform) -> Point {
        return Point(
            x: t.a * x + t.c * y + t.tx,
            y: t.b * x + t.d * y + t.ty
        )
    }
}

// MARK: - Affine Transform (CoreGraphics-independent)

public struct AffineTransform: Hashable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    @inlinable public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    @inlinable public static var identity: AffineTransform {
        AffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    }

    @inlinable public init(translationX tx: Double, y ty: Double) {
        self = .init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    @inlinable public init(scaleX sx: Double, y sy: Double) {
        self = .init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }
}

public struct Size: Hashable {
    public var width: Double
    public var height: Double

    @inlinable public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Rect: Hashable {
    public var origin: Point
    public var size: Size

    @inlinable public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    @inlinable public init(x: Double, y: Double, width: Double, height: Double) {
        origin = Point(x: x, y: y)
        size = Size(width: width, height: height)
    }

    @inlinable public var minX: Double { origin.x }
    @inlinable public var minY: Double { origin.y }
    @inlinable public var maxX: Double { origin.x + size.width }
    @inlinable public var maxY: Double { origin.y + size.height }
}

public struct Intersection: Equatable, Comparable {
    public var t1: Double
    public var t2: Double
    public static func < (lhs: Intersection, rhs: Intersection) -> Bool {
        if lhs.t1 < rhs.t1 {
            return true
        } else if lhs.t1 == rhs.t1 {
            return lhs.t2 < rhs.t2
        } else {
            return false
        }
    }
}

public struct Interval: Equatable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct BoundingBox: Equatable {
    public var min: Point
    public var max: Point

    public var rect: Rect {
        let s = size
        return Rect(origin: self.min, size: Size(width: s.x, height: s.y))
    }

    public static let empty: BoundingBox = .init(min: .infinity, max: -.infinity)
    init(min: Point, max: Point) {
        self.min = min
        self.max = max
    }

    @discardableResult public mutating func union(_ other: BoundingBox) -> BoundingBox {
        self.min = Point.min(self.min, other.min)
        self.max = Point.max(self.max, other.max)
        return self
    }

    @discardableResult public mutating func union(_ point: Point) -> BoundingBox {
        self.min = Point.min(self.min, point)
        self.max = Point.max(self.max, point)
        return self
    }

    public func intersection(_ other: BoundingBox) -> BoundingBox {
        let box = BoundingBox(min: Point.max(self.min, other.min),
                              max: Point.min(self.max, other.max))
        guard box.max.x - box.min.x >= 0, box.max.y - box.min.y >= 0 else {
            return BoundingBox.empty
        }
        return box
    }

    public var isEmpty: Bool {
        return self.min.x > self.max.x || self.min.y > self.max.y
    }

    public init(p1: Point, p2: Point) {
        self.min = Point.min(p1, p2)
        self.max = Point.max(p1, p2)
    }

    public init(first: BoundingBox, second: BoundingBox) {
        self.min = Point.min(first.min, second.min)
        self.max = Point.max(first.max, second.max)
    }

    public var size: Point {
        return Point.max(max - min, .zero)
    }

    var area: Double {
        let size = self.size
        return size.x * size.y
    }

    public func contains(_ point: Point) -> Bool {
        guard point.x >= min.x && point.x <= max.x else {
            return false
        }
        guard point.y >= min.y && point.y <= max.y else {
            return false
        }
        return true
    }

    public func overlaps(_ other: BoundingBox) -> Bool {
        let p1 = Point.max(self.min, other.min)
        let p2 = Point.min(self.max, other.max)
        return p2.x >= p1.x && p2.y >= p1.y
    }

    func lowerBoundOfDistance(to point: Point) -> Double {
        let distanceSquared = (0 ..< Point.dimensions).reduce(Double(0.0)) {
            let temp = point[$1] - Utils.clamp(point[$1], self.min[$1], self.max[$1])
            return $0 + temp * temp
        }
        return sqrt(distanceSquared)
    }

    func upperBoundOfDistance(to point: Point) -> Double {
        let distanceSquared = (0 ..< Point.dimensions).reduce(Double(0.0)) {
            let diff1 = point[$1] - self.min[$1]
            let diff2 = point[$1] - self.max[$1]
            return $0 + Double.maximum(diff1 * diff1, diff2 * diff2)
        }
        return sqrt(distanceSquared)
    }
}

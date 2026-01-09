//
//  CGPoint+Overloads.swift
//  BezierKit
//
//  Created by Holmes Futrell on 3/17/17.
//  Copyright © 2017 Holmes Futrell. All rights reserved.
//

import Foundation

// swiftlint:disable shorthand_operator

public extension Point {
    var length: Double {
        return sqrt(lengthSquared)
    }

    internal var lengthSquared: Double {
        return dot(self)
    }

    func normalize() -> Point {
        return self / length
    }

    internal static func min(_ p1: Point, _ p2: Point) -> Point {
        return Point(x: p1.x < p2.x ? p1.x : p2.x,
                     y: p1.y < p2.y ? p1.y : p2.y)
    }

    internal static func max(_ p1: Point, _ p2: Point) -> Point {
        return Point(x: p1.x > p2.x ? p1.x : p2.x,
                     y: p1.y > p2.y ? p1.y : p2.y)
    }

    internal var perpendicular: Point {
        return Point(x: -y, y: x)
    }
}

public func distance(_ p1: Point, _ p2: Point) -> Double {
    return (p1 - p2).length
}

public func distanceSquared(_ p1: Point, _ p2: Point) -> Double {
    return (p1 - p2).lengthSquared
}

private let badSubscriptError = "bad subscript (out of bounds)"

public extension Point {
    static let zero: Point = .init(x: 0, y: 0)
    internal static let infinity: Point = .init(x: Double.infinity, y: Double.infinity)

    internal static var dimensions: Int {
        return 2
    }

    func dot(_ other: Point) -> Double {
        return x * other.x + y * other.y
    }

    func cross(_ other: Point) -> Double {
        return x * other.y - y * other.x
    }

    subscript(index: Int) -> Double {
        get {
            assert(index == 0 || index == 1)
            if index == 0 {
                return x
            } else {
                return y
            }
        }
        set(newValue) {
            assert(index == 0 || index == 1)
            if index == 0 {
                x = newValue
            } else {
                y = newValue
            }
        }
    }

    static func + (left: Point, right: Point) -> Point {
        return Point(x: left.x + right.x, y: left.y + right.y)
    }

    static func - (left: Point, right: Point) -> Point {
        return Point(x: left.x - right.x, y: left.y - right.y)
    }

    static func += (left: inout Point, right: Point) {
        left = left + right
    }

    static func -= (left: inout Point, right: Point) {
        left = left - right
    }

    static func / (left: Point, right: Double) -> Point {
        return Point(x: left.x / right, y: left.y / right)
    }

    static func * (left: Double, right: Point) -> Point {
        return Point(x: left * right.x, y: left * right.y)
    }

    static prefix func - (point: Point) -> Point {
        return Point(x: -point.x, y: -point.y)
    }
}

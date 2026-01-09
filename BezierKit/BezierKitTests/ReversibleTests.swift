//
//  ReversibleTests.swift
//  BezierKit
//
//  Created by Holmes Futrell on 11/24/19.
//  Copyright © 2019 Holmes Futrell. All rights reserved.
//

import BezierKit
import XCTest

class ReversibleTests: XCTestCase {
    let lineSegment = LineSegment(p0: Point(x: 3, y: 5),
                                  p1: Point(x: 6, y: 7))
    let quadraticCurve = QuadraticCurve(p0: Point(x: 6, y: 7),
                                        p1: Point(x: 7, y: 5),
                                        p2: Point(x: 6, y: 3))
    let cubicCurve = CubicCurve(p0: Point(x: 6, y: 3),
                                p1: Point(x: 5, y: 2),
                                p2: Point(x: 4, y: 3),
                                p3: Point(x: 3, y: 5))
    let expectedReversedLineSegment = LineSegment(p0: Point(x: 6, y: 7),
                                                  p1: Point(x: 3, y: 5))
    let expectedReversedQuadraticCurve = QuadraticCurve(p0: Point(x: 6, y: 3),
                                                        p1: Point(x: 7, y: 5),
                                                        p2: Point(x: 6, y: 7))
    let expectedReversedCubicCurve = CubicCurve(p0: Point(x: 3, y: 5),
                                                p1: Point(x: 4, y: 3),
                                                p2: Point(x: 5, y: 2),
                                                p3: Point(x: 6, y: 3))

    func testReversibleLineSegment() {
        XCTAssertEqual(lineSegment.reversed(), expectedReversedLineSegment)
    }

    func testReversibleQuadraticCurve() {
        XCTAssertEqual(quadraticCurve.reversed(), expectedReversedQuadraticCurve)
    }

    func testReversibleCubicCurve() {
        XCTAssertEqual(cubicCurve.reversed(), expectedReversedCubicCurve)
    }

    func testReversiblePathComponent() {
        let component = PathComponent(curves: [lineSegment, quadraticCurve, cubicCurve])
        let expectedReversedComponent = PathComponent(curves: [expectedReversedCubicCurve, expectedReversedQuadraticCurve, expectedReversedLineSegment])
        XCTAssertEqual(component.reversed(), expectedReversedComponent)
    }

    func testReversiblePath() {
        let component1 = PathComponent(curve: LineSegment(p0: Point(x: 1, y: 2), p1: Point(x: 3, y: 4)))
        let component2 = PathComponent(curve: LineSegment(p0: Point(x: 1, y: -2), p1: Point(x: 3, y: 5)))
        let path = Path(components: [component1, component2])
        let reversedComponent1 = PathComponent(curve: LineSegment(p0: Point(x: 3, y: 4), p1: Point(x: 1, y: 2)))
        let reversedComponent2 = PathComponent(curve: LineSegment(p0: Point(x: 3, y: 5), p1: Point(x: 1, y: -2)))
        let expectedRerversedPath = Path(components: [reversedComponent1, reversedComponent2])
        XCTAssertEqual(path.reversed(), expectedRerversedPath)
    }
}

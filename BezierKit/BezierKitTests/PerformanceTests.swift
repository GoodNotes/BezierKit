//
//  PerformanceTests.swift
//  BezierKit
//
//  Created by Holmes Futrell on 5/3/21.
//  Copyright © 2021 Holmes Futrell. All rights reserved.
//

import BezierKit
import XCTest

#if !os(WASI)
    private extension PerformanceTests {
        func generateRandomCurves(count: Int, selfIntersect: Bool? = nil, reseed: Int? = nil) -> [CubicCurve] {
            if let reseed = reseed {
                srand48(reseed) // seed with zero so that "random" values are actually the same across test runs
            }
            func randomPoint() -> Point {
                let x = Double(drand48())
                let y = Double(drand48())
                return Point(x: x, y: y)
            }
            func randomCurve() -> CubicCurve {
                return CubicCurve(p0: randomPoint(),
                                  p1: randomPoint(),
                                  p2: randomPoint(),
                                  p3: randomPoint())
            }
            var curves: [CubicCurve] = []
            while curves.count < count {
                let curve = randomCurve()
                if selfIntersect == nil || curve.selfIntersects == selfIntersect {
                    curves.append(curve)
                }
            }
            return curves
        }

        #if canImport(CoreGraphics)

            func parametricPath(numCurves: Int,
                                theta: (_: Double) -> Double,
                                dthetadt: (_: Double) -> Double,
                                r: (_: Double) -> Double,
                                drdt: (_: Double) -> Double) -> Path
            {
                func p(_ t: Double) -> Point {
                    return Point(x: r(t) * cos(theta(t)), y: r(t) * sin(theta(t)))
                }
                func d(_ t: Double) -> Point {
                    return Point(x: drdt(t) * cos(theta(t)) - r(t) * sin(theta(t)) * dthetadt(t),
                                 y: drdt(t) * sin(theta(t)) + r(t) * cos(theta(t)) * dthetadt(t))
                }
                let cgPath = CGMutablePath()
                var previousT = 0.0
                var previousPoint = p(previousT)
                cgPath.move(to: previousPoint)
                let delta = 1.0 / Double(numCurves)
                for i in 1 ... numCurves {
                    let nextT = Double(i) / Double(numCurves)
                    let nextPoint = p(nextT)
                    cgPath.addCurve(to: nextPoint, control1: previousPoint + delta / 3.0 * d(previousT), control2: nextPoint - delta / 3.0 * d(nextT))
                    previousPoint = nextPoint
                    previousT = nextT
                }
                return Path(cgPath: cgPath)
            }

        #endif
    }

    class PerformanceTests: XCTestCase {
        func testCubicSelfIntersectionsPerformanceNoIntersect() {
            // test the performance of `selfIntersections` when the curves DO NOT self-intersect
            // -Onone 0.036 seconds
            // -Os 0.004 seconds
            let dataCount = 100_000
            let curves = generateRandomCurves(count: dataCount, selfIntersect: false, reseed: 0)
            measure {
                var count = 0
                for curve in curves {
                    count += curve.selfIntersections.count
                }
                XCTAssertEqual(count, 0)
            }
        }

        func testCubicSelfIntersectionsPerformanceYesIntersect() {
            // test the performance of `selfIntersections` when the curves self-intersect
            // -Onone 0.048 seconds
            // -Os 0.014 seconds
            let dataCount = 100_000
            let curves = generateRandomCurves(count: dataCount, selfIntersect: true, reseed: 1)
            measure {
                var count = 0
                for curve in curves {
                    count += curve.selfIntersections.count
                }
                XCTAssertEqual(count, dataCount)
            }
        }

        func testCubicIntersectionsPerformance() {
            // test the performance of `intersections(with:,accuracy:)`
            // -Onone 0.57 seconds
            // -Os 0.075 seconds
            let dataCount = 50
            let curves = generateRandomCurves(count: dataCount, reseed: 2)
            measure {
                var count = 0
                for curve1 in curves {
                    for curve2 in curves {
                        count += curve1.intersections(with: curve2, accuracy: 1.0e-5).count
                    }
                }
            }
        }

        func testCubicIntersectionsPerformanceTangentEndpoint() {
            // test the performance of `intersections(with:,accuracy:)`
            // -Onone 0.89 seconds
            // -Os 0.059 seconds
            let dataCount = 250
            let curves = generateRandomCurves(count: dataCount, reseed: 3)
            measure {
                var count = 0
                for curve1 in curves {
                    // create a curve that starts at the other curve's endpoint
                    // and whose first tangent double's back on the curve
                    // this is a difficult edge case for divide-and-conquer
                    // algorithms
                    let curve2 = CubicCurve(p0: curve1.endingPoint,
                                            p1: Double(drand48()) * (curve1.p2 - curve1.p3) + curve1.endingPoint,
                                            p2: Point(x: drand48(), y: drand48()),
                                            p3: Point(x: drand48(), y: drand48()))
                    count += curve1.intersections(with: curve2, accuracy: 1.0e-5).count
                }
            }
        }

        func testQuadraticCurveProjectPerformance() {
            let q = QuadraticCurve(p0: Point(x: -1, y: -1),
                                   p1: Point(x: 0, y: 2),
                                   p2: Point(x: 1, y: -1))
            measure {
                // roughly 0.043 -Onone, 0.022 with -Ospeed
                // if comparing with cubic performance, be sure to note `by` parameter in stride
                for theta in stride(from: 0, to: 2 * Double.pi, by: 0.0001) {
                    _ = q.project(Point(x: cos(theta), y: sin(theta)))
                }
            }
        }

        func testCubicCurveProjectPerformance() {
            let c = CubicCurve(p0: Point(x: -1, y: -1),
                               p1: Point(x: 3, y: 1),
                               p2: Point(x: -3, y: 1),
                               p3: Point(x: 1, y: -1))
            measure {
                // roughly 0.029 -Onone, 0.004 with -Ospeed
                for theta in stride(from: 0, to: 2 * Double.pi, by: 0.01) {
                    _ = c.project(Point(x: cos(theta), y: sin(theta)))
                }
            }
        }

        #if canImport(CoreGraphics)

            func testPathProjectPerformance() {
                let k = 2.0 * Double.pi * 10
                let maxRadius = 100.0
                func theta(_ t: Double) -> Double {
                    return k * t
                }
                func r(_ t: Double) -> Double {
                    return t * maxRadius
                }
                func drdt(_: Double) -> Double {
                    return maxRadius
                }
                func dthetadt(_: Double) -> Double {
                    return k
                }
                let spiral = parametricPath(numCurves: 100, theta: theta, dthetadt: dthetadt, r: r, drdt: drdt)
                // about 0.31s in -Onone, 0.033s in -Ospeed
                measure {
                    var pointsTested = 0
                    var totalDistance = 0.0
                    for x in stride(from: -maxRadius, through: maxRadius, by: 10) {
                        for y in stride(from: -maxRadius, through: maxRadius, by: 10) {
                            // print("(\(x), \(y))")
                            let point = Point(x: x, y: y)
                            let projection = spiral.project(point)!.point
                            pointsTested += 1
                            totalDistance += distance(projection, point)
                        }
                    }
                    // print("tested \(pointsTested) points, average distance from spiral = \(totalDistance / Double(pointsTested))")
                }
            }

            func testPathSubtractionPerformance() {
                func circlePath(origin: Point, radius: Double, numPoints: Int) -> Path {
                    let c = 0.551915024494 * radius * 4.0 / Double(numPoints)
                    let cgPath = CGMutablePath()
                    var lastPoint = origin + Point(x: radius, y: 0.0)
                    var lastTangent = Point(x: 0.0, y: c)
                    cgPath.move(to: lastPoint)
                    for i in 1 ... numPoints {
                        let theta = Double(2.0 * Double.pi) * Double(i % numPoints) / Double(numPoints)
                        let cosTheta = cos(theta)
                        let sinTheta = sin(theta)
                        let point = origin + radius * Point(x: cosTheta, y: sinTheta)
                        let tangent = c * Point(x: -sinTheta, y: cosTheta)
                        cgPath.addCurve(to: point, control1: lastPoint + lastTangent, control2: point - tangent)
                        //  cgPath.addLine(to: point)
                        lastPoint = point
                        lastTangent = tangent
                    }
                    return Path(cgPath: cgPath)
                }
                let numPoints = 300
                let path1 = circlePath(origin: Point(x: 0, y: 0), radius: 100, numPoints: numPoints)
                let path2 = circlePath(origin: Point(x: 1, y: 0), radius: 100, numPoints: numPoints)
                measure { // roughly 0.018s in debug mode
                    _ = path1.subtract(path2, accuracy: 1.0e-3)
                }
            }

        #endif
    }
#endif

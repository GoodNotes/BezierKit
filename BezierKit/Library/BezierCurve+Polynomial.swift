//
//  BezierCurve+Polynomial.swift
//  BezierKit
//
//  Created by Holmes Futrell on 1/22/21.
//  Copyright © 2021 Holmes Futrell. All rights reserved.
//

/// a parametric function whose x and y coordinates can be considered as separate polynomial functions
/// eg `f(t) = (xPolynomial(t), yPolynomial(t))`
public protocol ComponentPolynomials {
    associatedtype Polynomial: BernsteinPolynomial
    var xPolynomial: Polynomial { get }
    var yPolynomial: Polynomial { get }
}

extension LineSegment: ComponentPolynomials {
    public var xPolynomial: BernsteinPolynomial1 { return BernsteinPolynomial1(b0: p0.x, b1: p1.x) }
    public var yPolynomial: BernsteinPolynomial1 { return BernsteinPolynomial1(b0: p0.y, b1: p1.y) }
}

extension QuadraticCurve: ComponentPolynomials {
    public var xPolynomial: BernsteinPolynomial2 { return BernsteinPolynomial2(b0: p0.x, b1: p1.x, b2: p2.x) }
    public var yPolynomial: BernsteinPolynomial2 { return BernsteinPolynomial2(b0: p0.y, b1: p1.y, b2: p2.y) }
}

extension CubicCurve: ComponentPolynomials {
    public var xPolynomial: BernsteinPolynomial3 { return BernsteinPolynomial3(b0: p0.x, b1: p1.x, b2: p2.x, b3: p3.x) }
    public var yPolynomial: BernsteinPolynomial3 { return BernsteinPolynomial3(b0: p0.y, b1: p1.y, b2: p2.y, b3: p3.y) }
}

public extension BezierCurve where Self: ComponentPolynomials {
    /// default implementation of `extrema` by finding roots of component polynomials
    func extrema() -> (x: [Double], y: [Double], all: [Double]) {
        func rootsForPolynomial<B: BernsteinPolynomial>(_ polynomial: B) -> [Double] {
            let firstOrderDerivative = polynomial.derivative
            var roots = findDistinctRootsInUnitInterval(of: firstOrderDerivative)
            if order >= 3 {
                let secondOrderDerivative = firstOrderDerivative.derivative
                roots += findDistinctRootsInUnitInterval(of: secondOrderDerivative)
            }
            return roots.sortedAndUniqued()
        }
        let xRoots = rootsForPolynomial(xPolynomial)
        let yRoots = rootsForPolynomial(yPolynomial)
        let allRoots = (xRoots + yRoots).sortedAndUniqued()
        return (x: xRoots, y: yRoots, all: allRoots)
    }
}

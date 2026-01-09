//
//  Path.swift
//  BezierKit
//
//  Created by Holmes Futrell on 7/31/18.
//  Copyright © 2018 Holmes Futrell. All rights reserved.
//

import Foundation

private extension Array {
    /// if an array has unused capacity returns a new array where `self.count == self.capacity`
    /// can save memory when an array is immutable after adding some initial items
    var copyByTrimmingReservedCapacity: Self {
        guard capacity > count else { return self }
        return withUnsafeBufferPointer { Self($0) }
    }
}

@objc(BezierKitPathFillRule) public enum PathFillRule: NSInteger {
    case winding = 0, evenOdd
}

func windingCountImpliesContainment(_ count: Int, using rule: PathFillRule) -> Bool {
    switch rule {
    case .winding:
        return count != 0
    case .evenOdd:
        return count % 2 != 0
    }
}

open class Path: NSObject {
    /// lock to make external accessing of lazy vars threadsafe
    private let lock = UnfairLock()

    public var isEmpty: Bool {
        return components.isEmpty // components are not allowed to be empty
    }

    public var boundingBox: BoundingBox {
        return lock.sync { self._boundingBox }
    }

    /// the smallest bounding box completely enclosing the points of the path, includings its control points.
    public var boundingBoxOfPath: BoundingBox {
        return lock.sync { self._boundingBoxOfPath }
    }

    private lazy var _boundingBox: BoundingBox = self.components.reduce(BoundingBox.empty) {
        BoundingBox(first: $0, second: $1.boundingBox)
    }

    private lazy var _boundingBoxOfPath: BoundingBox = self.components.reduce(BoundingBox.empty) {
        BoundingBox(first: $0, second: $1.boundingBoxOfPath)
    }

    private var _hash: Int?

    public let components: [PathComponent]

    public func selfIntersects(accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Bool {
        return !selfIntersections(accuracy: accuracy).isEmpty
    }

    public func selfIntersections(accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> [PathIntersection] {
        var intersections: [PathIntersection] = []
        for i in 0 ..< components.count {
            for j in i ..< components.count {
                let componentIntersectionToPathIntersection = { (componentIntersection: PathComponentIntersection) -> PathIntersection in
                    PathIntersection(componentIntersection: componentIntersection, componentIndex1: i, componentIndex2: j)
                }
                if i == j {
                    intersections += components[i].selfIntersections(accuracy: accuracy).map(componentIntersectionToPathIntersection)
                } else {
                    intersections += components[i].intersections(with: components[j], accuracy: accuracy).map(componentIntersectionToPathIntersection)
                }
            }
        }
        return intersections
    }

    public func intersects(_ other: Path, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Bool {
        return !intersections(with: other, accuracy: accuracy).isEmpty
    }

    public func intersections(with other: Path, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> [PathIntersection] {
        guard boundingBox.overlaps(other.boundingBox) else {
            return []
        }
        var intersections: [PathIntersection] = []
        for i in 0 ..< components.count {
            for j in 0 ..< other.components.count {
                let componentIntersectionToPathIntersection = { (componentIntersection: PathComponentIntersection) -> PathIntersection in
                    PathIntersection(componentIntersection: componentIntersection, componentIndex1: i, componentIndex2: j)
                }
                let s1 = components[i]
                let s2 = other.components[j]
                let componentIntersections: [PathComponentIntersection] = s1.intersections(with: s2, accuracy: accuracy)
                intersections += componentIntersections.map(componentIntersectionToPathIntersection)
            }
        }
        return intersections
    }

    #if canImport(ObjectiveC)
        @objc override public convenience init() {
            self.init(components: [])
        }
    #else
        override public convenience init() {
            self.init(components: [])
        }
    #endif

    public required init(components: [PathComponent]) {
        self.components = components
    }

    public convenience init(curve: BezierCurve) {
        self.init(components: [PathComponent(curve: curve)])
    }

    convenience init(rect: Rect) {
        let o = rect.origin
        let points = [o,
                      Point(x: o.x + rect.size.width, y: o.y),
                      Point(x: o.x + rect.size.width, y: o.y + rect.size.height),
                      Point(x: o.x, y: o.y + rect.size.height),
                      o]
        let component = PathComponent(points: points, orders: [Int](repeating: 1, count: 4))
        self.init(components: [component])
    }

    // MARK: - NSCoding

    // (cannot be put in extension because init?(coder:) is a designated initializer)

    public static var supportsSecureCoding: Bool {
        return true
    }

    #if !os(WASI)
        public func encode(with aCoder: NSCoder) {
            aCoder.encode(data)
        }

        public required convenience init?(coder aDecoder: NSCoder) {
            guard let data = aDecoder.decodeData() else { return nil }
            self.init(data: data)
        }
    #endif

    // MARK: -

    override open func isEqual(_ object: Any?) -> Bool {
        // override is needed because NSObject implementation of isEqual(_:) uses pointer equality
        guard let otherPath = object as? Path else {
            return false
        }
        return components == otherPath.components
    }

    private func assertValidComponent(_ location: IndexedPathLocation) {
        assert(location.componentIndex >= 0 && location.componentIndex < components.count)
    }

    public func point(at location: IndexedPathLocation) -> Point {
        assertValidComponent(location)
        return components[location.componentIndex].point(at: location.locationInComponent)
    }

    public func derivative(at location: IndexedPathLocation) -> Point {
        assertValidComponent(location)
        return components[location.componentIndex].derivative(at: location.locationInComponent)
    }

    public func normal(at location: IndexedPathLocation) -> Point {
        assertValidComponent(location)
        return components[location.componentIndex].normal(at: location.locationInComponent)
    }

    func windingCount(_ point: Point, ignoring: PathComponent? = nil) -> Int {
        let windingCount = components.reduce(0) {
            if $1 !== ignoring {
                return $0 + $1.windingCount(at: point)
            } else {
                return $0
            }
        }
        return windingCount
    }

    public func contains(_ point: Point, using rule: PathFillRule = .winding) -> Bool {
        let count = windingCount(point)
        return windingCountImpliesContainment(count, using: rule)
    }

    public func contains(_ other: Path, using rule: PathFillRule = .winding, accuracy: Double = BezierKit.defaultIntersectionAccuracy) -> Bool {
        // first, check that each component of `other` starts inside self
        for component in other.components {
            let p = component.startingPoint
            guard contains(p, using: rule) else {
                return false
            }
        }
        // next, for each intersection (if there are any) check that we stay inside the path
        // TODO: use enumeration over intersections so we don't have to necessarily have to find each one
        // TODO: make this work with winding fill rule and intersections that don't cross (suggestion, use AugmentedGraph)
        return !intersects(other, accuracy: accuracy)
    }

    public func offset(distance d: Double) -> Path {
        return Path(components: components.compactMap {
            $0.offset(distance: d)
        })
    }

    public func disjointComponents() -> [Path] {
        let rule: PathFillRule = .evenOdd
        var outerComponents: [PathComponent: [PathComponent]] = [:]
        var innerComponents: [PathComponent] = []
        // determine which components are outer and which are inner
        for component in components {
            let windingCount = self.windingCount(component.startingPoint, ignoring: component)
            if windingCountImpliesContainment(windingCount, using: rule) {
                innerComponents.append(component)
            } else {
                outerComponents[component] = [component]
            }
        }
        // file the inner components into their "owning" outer components
        for component in innerComponents {
            var owner: PathComponent?
            for outer in outerComponents.keys {
                if let owner = owner {
                    guard outer.boundingBox.intersection(owner.boundingBox) == outer.boundingBox else { continue }
                }
                if outer.contains(component.startingPoint, using: rule) {
                    owner = outer
                }
            }
            if let owner = owner {
                outerComponents[owner]?.append(component)
            }
        }
        return outerComponents.values.map { Path(components: $0) }
    }

    override public var hash: Int {
        // override is needed because NSObject hashing is independent of Swift's Hashable
        return lock.sync {
            if let _hash = _hash { return _hash }
            var hasher = Hasher()
            for component in components {
                hasher.combine(component)
            }
            let h = hasher.finalize()
            _hash = h
            return h
        }
    }
}

#if !os(WASI)
    extension Path: NSSecureCoding {}
#endif

extension Path: Transformable {
    public func copy(using t: AffineTransform) -> Self {
        return type(of: self).init(components: components.map { $0.copy(using: t) })
    }
}

extension Path: Reversible {
    public func reversed() -> Self {
        return type(of: self).init(components: components.map { $0.reversed() })
    }
}

public struct IndexedPathLocation: Equatable, Comparable {
    public let componentIndex: Int
    public let elementIndex: Int
    public let t: Double
    public init(componentIndex: Int, elementIndex: Int, t: Double) {
        self.componentIndex = componentIndex
        self.elementIndex = elementIndex
        self.t = t
    }

    public init(componentIndex: Int, locationInComponent: IndexedPathComponentLocation) {
        self.init(componentIndex: componentIndex, elementIndex: locationInComponent.elementIndex, t: locationInComponent.t)
    }

    public static func < (lhs: IndexedPathLocation, rhs: IndexedPathLocation) -> Bool {
        if lhs.componentIndex < rhs.componentIndex {
            return true
        } else if lhs.componentIndex > rhs.componentIndex {
            return false
        }
        if lhs.elementIndex < rhs.elementIndex {
            return true
        } else if lhs.elementIndex > rhs.elementIndex {
            return false
        }
        return lhs.t < rhs.t
    }

    public var locationInComponent: IndexedPathComponentLocation {
        return IndexedPathComponentLocation(elementIndex: elementIndex, t: t)
    }
}

public struct PathIntersection: Equatable {
    public let indexedPathLocation1, indexedPathLocation2: IndexedPathLocation
    init(indexedPathLocation1: IndexedPathLocation, indexedPathLocation2: IndexedPathLocation) {
        self.indexedPathLocation1 = indexedPathLocation1
        self.indexedPathLocation2 = indexedPathLocation2
    }

    fileprivate init(componentIntersection: PathComponentIntersection, componentIndex1: Int, componentIndex2: Int) {
        indexedPathLocation1 = IndexedPathLocation(componentIndex: componentIndex1, locationInComponent: componentIntersection.indexedComponentLocation1)
        indexedPathLocation2 = IndexedPathLocation(componentIndex: componentIndex2, locationInComponent: componentIntersection.indexedComponentLocation2)
    }
}

#if canImport(CoreGraphics)
    import CoreGraphics
    import Foundation

    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif

    // MARK: - Geometry bridging

    public extension Point {
        @inlinable init(_ cgPoint: CGPoint) { self.init(x: cgPoint.x, y: cgPoint.y) }
        @inlinable var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    }

    public extension Size {
        @inlinable init(_ cgSize: CGSize) { self.init(width: cgSize.width, height: cgSize.height) }
        @inlinable var cgSize: CGSize { CGSize(width: width, height: height) }
    }

    public extension Rect {
        @inlinable init(origin: Point, size: CGSize) {
            self.init(origin: origin, size: Size(size))
        }

        @inlinable init(_ cgRect: CGRect) {
            self.init(x: cgRect.origin.x, y: cgRect.origin.y, width: cgRect.size.width, height: cgRect.size.height)
        }

        @inlinable var cgRect: CGRect {
            CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        }
    }

    public extension BoundingBox {
        @inlinable var cgRect: CGRect { rect.cgRect }
    }

    public extension AffineTransform {
        @inlinable init(_ t: CGAffineTransform) {
            self.init(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty)
        }

        @inlinable var cgAffineTransform: CGAffineTransform {
            CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
        }
    }

    // MARK: - PathComponent <-> CGPath boundary

    extension PathComponent {
        func apply(info: UnsafeMutableRawPointer?, function: CGPathApplierFunction) {
            let numberOfElements = self.numberOfElements
            let isClosed = self.isClosed
            // Emit CGPath elements from our `Point` storage, converting to `CGPoint` only at the boundary.
            // Storage format matches the original implementation:
            // - `points[0]` is the starting/moveTo point
            // - for each element with order N, the next N points are that element's points

            // moveTo
            var moveToPoint = points[0].cgPoint
            withUnsafeMutablePointer(to: &moveToPoint) { ptr in
                var element = CGPathElement(type: .moveToPoint, points: ptr)
                function(info, &element)
            }

            var pointIndex = 1
            for i in 0 ..< numberOfElements {
                let order = orders[i]
                guard order != 0 else { break } // point component: just the moveTo

                let isLast = (i == numberOfElements - 1)
                let type: CGPathElementType
                let neededPoints: Int

                switch order {
                case 1:
                    if isLast, isClosed {
                        type = .closeSubpath
                        neededPoints = 0
                    } else {
                        type = .addLineToPoint
                        neededPoints = 1
                    }
                case 2:
                    type = .addQuadCurveToPoint
                    neededPoints = 2
                case 3:
                    type = .addCurveToPoint
                    neededPoints = 3
                default:
                    assertionFailure("unexpected curve order \(order). Expected between 0 (point) and 3 (cubic curve).")
                    return
                }

                if neededPoints == 0 {
                    var dummy = CGPoint.zero
                    withUnsafeMutablePointer(to: &dummy) { ptr in
                        var element = CGPathElement(type: type, points: ptr)
                        function(info, &element)
                    }
                } else {
                    let cgPoints: [CGPoint] = (0 ..< neededPoints).map { j in
                        self.points[pointIndex + j].cgPoint
                    }
                    cgPoints.withUnsafeBufferPointer { buf in
                        // CGPathElement expects a mutable pointer, but the function should not mutate it.
                        var element = CGPathElement(type: type, points: UnsafeMutablePointer(mutating: buf.baseAddress!))
                        function(info, &element)
                    }
                }

                // advance over the stored points for this element (even if we emitted closeSubpath)
                pointIndex += order
            }
        }

        func appendPath(to mutablePath: CGMutablePath) {
            let numberOfElements = self.numberOfElements
            let isClosed = self.isClosed

            mutablePath.move(to: points[0].cgPoint)

            var pointIndex = 1
            for i in 0 ..< numberOfElements {
                let order = orders[i]
                guard order != 0 else { break }

                let isLast = (i == numberOfElements - 1)
                switch order {
                case 1:
                    if isLast, isClosed {
                        mutablePath.closeSubpath()
                    } else {
                        mutablePath.addLine(to: points[pointIndex].cgPoint)
                    }
                case 2:
                    mutablePath.addQuadCurve(to: points[pointIndex + 1].cgPoint,
                                             control: points[pointIndex].cgPoint)
                case 3:
                    mutablePath.addCurve(to: points[pointIndex + 2].cgPoint,
                                         control1: points[pointIndex].cgPoint,
                                         control2: points[pointIndex + 1].cgPoint)
                default:
                    assertionFailure("unexpected curve order \(order). Expected between 0 (point) and 3 (cubic curve).")
                    return
                }
                pointIndex += order
            }
        }
    }

    // MARK: - Path <-> CGPath boundary

    private let _pathCGPathCacheLock = UnfairLock()
    private let _pathCGPathCache = NSMapTable<Path, CGPath>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    public extension Path {
        var cgPath: CGPath {
            _pathCGPathCacheLock.sync {
                if let cached = _pathCGPathCache.object(forKey: self) {
                    return cached
                }
                let mutablePath = CGMutablePath()
                for component in self.components {
                    component.appendPath(to: mutablePath)
                }
                let built = mutablePath.copy()!
                _pathCGPathCache.setObject(built, forKey: self)
                return built
            }
        }

        convenience init(cgPath: CGPath) {
            final class PathApplierFunctionContext {
                var currentPoint: Point?
                var componentStartPoint: Point?

                var currentComponentPoints: [Point] = []
                var currentComponentOrders: [Int] = []

                var components: [PathComponent] = []
                func completeComponentIfNeededAndClearPointsAndOrders() {
                    if currentComponentPoints.isEmpty == false {
                        if currentComponentOrders.isEmpty == true {
                            currentComponentOrders.append(0)
                        }
                        components.append(PathComponent(points: currentComponentPoints,
                                                        orders: currentComponentOrders))
                    }
                    currentComponentPoints = []
                    currentComponentOrders = []
                }

                func appendCurrentPointIfEmpty() {
                    if currentComponentPoints.isEmpty {
                        currentComponentPoints = [currentPoint!]
                    }
                }
            }

            let context = PathApplierFunctionContext()
            func applierFunction(_ ctx: UnsafeMutableRawPointer?, _ element: UnsafePointer<CGPathElement>) {
                guard let context = ctx?.assumingMemoryBound(to: PathApplierFunctionContext.self).pointee else {
                    fatalError("unexpected applierFunction context")
                }
                let points: UnsafeMutablePointer<CGPoint> = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint:
                    context.completeComponentIfNeededAndClearPointsAndOrders()
                    context.componentStartPoint = Point(points[0])
                    context.currentComponentOrders = []
                    context.currentComponentPoints = [Point(points[0])]
                    context.currentPoint = Point(points[0])
                case .addLineToPoint:
                    context.appendCurrentPointIfEmpty()
                    context.currentComponentOrders.append(1)
                    context.currentComponentPoints.append(Point(points[0]))
                    context.currentPoint = Point(points[0])
                case .addQuadCurveToPoint:
                    context.appendCurrentPointIfEmpty()
                    context.currentComponentOrders.append(2)
                    context.currentComponentPoints.append(Point(points[0]))
                    context.currentComponentPoints.append(Point(points[1]))
                    context.currentPoint = Point(points[1])
                case .addCurveToPoint:
                    context.appendCurrentPointIfEmpty()
                    context.currentComponentOrders.append(3)
                    context.currentComponentPoints.append(Point(points[0]))
                    context.currentComponentPoints.append(Point(points[1]))
                    context.currentComponentPoints.append(Point(points[2]))
                    context.currentPoint = Point(points[2])
                case .closeSubpath:
                    if context.currentPoint != context.componentStartPoint {
                        context.currentComponentOrders.append(1)
                        context.currentComponentPoints.append(context.componentStartPoint!)
                    }
                    context.completeComponentIfNeededAndClearPointsAndOrders()
                    context.currentPoint = context.componentStartPoint!
                @unknown default:
                    fatalError("unexpected unknown path element type \(element.pointee.type)")
                }
            }
            withUnsafePointer(to: context) {
                let rawPointer = UnsafeMutableRawPointer(mutating: $0)
                cgPath.apply(info: rawPointer, function: applierFunction)
            }
            context.completeComponentIfNeededAndClearPointsAndOrders()
            self.init(components: context.components)
        }

        func apply(info: UnsafeMutableRawPointer?, function: CGPathApplierFunction) {
            for component in components {
                component.apply(info: info, function: function)
            }
        }

        internal convenience init(rect: CGRect) {
            self.init(rect: Rect(rect))
        }
    }

    // MARK: - Draw (CoreGraphics-only)

    // should Draw just be an extension of CGContext, or have a CGContext instead of passing it in to all these functions?
    public class Draw {
        private static let deviceColorspace = CGColorSpaceCreateDeviceRGB()

        // MARK: - helpers

        private static func Color(red: Double, green: Double, blue: Double, alpha: Double) -> CGColor {
            // have to use this initializer because simpler one is MacOS 10.5+ (not iOS)
            return CGColor(colorSpace: Draw.deviceColorspace, components: [red, green, blue, alpha])!
        }

        /**
         * HSL to RGB converter.
         * Adapted from: https://github.com/alessani/ColorConverter
         */
        static func HSLToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
            // Check for saturation. If there isn't any just return the luminance value for each, which results in gray.
            if s == 0.0 {
                return (r: l, g: l, b: l)
            }

            var temp1, temp2: Double
            var temp: [Double] = [0, 0, 0]

            // Test for luminance and compute temporary values based on luminance and saturation
            if l < 0.5 {
                temp2 = l * (1.0 + s)
            } else {
                temp2 = l + s - l * s
            }
            temp1 = 2.0 * l - temp2

            // Compute intermediate values based on hue
            temp[0] = h + 1.0 / 3.0
            temp[1] = h
            temp[2] = h - 1.0 / 3.0

            for i in 0 ..< 3 {
                // Adjust the range
                if temp[i] < 0.0 {
                    temp[i] += 1.0
                } else if temp[i] > 1.0 {
                    temp[i] -= 1.0
                }

                if (6.0 * temp[i]) < 1.0 {
                    temp[i] = temp1 + (temp2 - temp1) * 6.0 * temp[i]
                } else if (2.0 * temp[i]) < 1.0 {
                    temp[i] = temp2
                } else if (3.0 * temp[i]) < 2.0 {
                    temp[i] = temp1 + (temp2 - temp1) * ((2.0 / 3.0) - temp[i]) * 6.0
                } else {
                    temp[i] = temp1
                }
            }
            // Assign temporary values to R, G, B
            return (r: temp[0], g: temp[1], b: temp[2])
        }

        // MARK: - some useful hard-coded colors

        public static let lightGrey = Draw.Color(red: 211.0 / 255.0, green: 211.0 / 255.0, blue: 211.0 / 255.0, alpha: 1.0)
        public static let black = Draw.Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        public static let red = Draw.Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        public static let pinkish = Draw.Color(red: 1.0, green: 100.0 / 255.0, blue: 100.0 / 255.0, alpha: 1.0)
        public static let transparentBlue = Draw.Color(red: 0.0, green: 0.0, blue: 1.0, alpha: 0.3)
        public static let transparentBlack = Draw.Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.2)
        public static let blue = Draw.Color(red: 0.0, green: 0.0, blue: 255.0, alpha: 1.0)
        public static let green = Draw.Color(red: 0.0, green: 255.0, blue: 0.0, alpha: 1.0)

        private static var randomIndex = 0
        private static let randomColors: [CGColor] = {
            var temp: [CGColor] = []
            for i in 0 ..< 360 {
                var j = (i * 47) % 360
                let (r, g, b) = HSLToRGB(h: Double(j) / 360.0, s: 0.5, l: 0.5)
                temp.append(Draw.Color(red: r, green: g, blue: b, alpha: 1.0))
            }
            return temp
        }()

        // MARK: -

        public static func reset(_ context: CGContext) {
            context.setStrokeColor(black)
            randomIndex = 0
        }

        // MARK: - setting colors

        public static func setRandomColor(_ context: CGContext) {
            randomIndex = (randomIndex + 1) % randomColors.count
            let c = randomColors[randomIndex]
            context.setStrokeColor(c)
        }

        public static func setRandomFill(_ context: CGContext, alpha a: Double = 1.0) {
            randomIndex = (randomIndex + 1) % randomColors.count
            let c = randomColors[randomIndex]
            let c2 = c.copy(alpha: a)
            context.setFillColor(c2!)
        }

        public static func setColor(_ context: CGContext, color: CGColor) {
            context.setStrokeColor(color)
        }

        // MARK: - drawing various geometry

        public static func drawCurve(_ context: CGContext, curve: BezierCurve, offset: CGPoint = .zero) {
            @inline(__always) func addOffset(_ p: Point) -> CGPoint {
                CGPoint(x: p.x + offset.x, y: p.y + offset.y)
            }
            context.beginPath()
            if let quadraticCurve = curve as? QuadraticCurve {
                context.move(to: addOffset(quadraticCurve.p0))
                context.addQuadCurve(to: addOffset(quadraticCurve.p2),
                                     control: addOffset(quadraticCurve.p1))
            } else if let cubicCurve = curve as? CubicCurve {
                context.move(to: addOffset(cubicCurve.p0))
                context.addCurve(to: addOffset(cubicCurve.p3),
                                 control1: addOffset(cubicCurve.p1),
                                 control2: addOffset(cubicCurve.p2))
            } else if let lineSegment = curve as? LineSegment {
                context.move(to: addOffset(lineSegment.p0))
                context.addLine(to: addOffset(lineSegment.p1))
            } else {
                fatalError("unsupported curve type")
            }
            context.strokePath()
        }

        public static func drawCircle(_ context: CGContext, center: CGPoint, radius r: Double, offset: CGPoint = .zero) {
            context.beginPath()
            context.addEllipse(in: CGRect(origin: CGPoint(x: center.x - r + offset.x, y: center.y - r + offset.y),
                                          size: CGSize(width: 2.0 * r, height: 2.0 * r))
            )
            context.strokePath()
        }

        public static func drawPoint(_ context: CGContext, origin o: CGPoint, offset: CGPoint = .zero) {
            drawCircle(context, center: o, radius: 5.0, offset: offset)
        }

        public static func drawPoints(_ context: CGContext,
                                      points: [CGPoint],
                                      offset: CGPoint = CGPoint(x: 0.0, y: 0.0))
        {
            for p in points {
                drawCircle(context, center: p, radius: 3.0, offset: offset)
            }
        }

        public static func drawLine(_ context: CGContext,
                                    from p0: CGPoint,
                                    to p1: CGPoint,
                                    offset: CGPoint = CGPoint(x: 0.0, y: 0.0))
        {
            context.beginPath()
            context.move(to: CGPoint(x: p0.x + offset.x, y: p0.y + offset.y))
            context.addLine(to: CGPoint(x: p1.x + offset.x, y: p1.y + offset.y))
            context.strokePath()
        }

        public static func drawText(_: CGContext, text: String, offset: CGPoint = .zero) {
            #if os(macOS)
                (text as NSString).draw(at: NSPoint(x: offset.x, y: offset.y), withAttributes: [:])
            #else
                (text as NSString).draw(at: CGPoint(x: offset.x, y: offset.y), withAttributes: [:])
            #endif
        }

        public static func drawSkeleton(_ context: CGContext,
                                        curve: BezierCurve,
                                        offset: CGPoint = CGPoint(x: 0.0, y: 0.0),
                                        coords: Bool = true)
        {
            context.setStrokeColor(lightGrey)

            if let cubicCurve = curve as? CubicCurve {
                drawLine(context, from: cubicCurve.p0.cgPoint, to: cubicCurve.p1.cgPoint, offset: offset)
                drawLine(context, from: cubicCurve.p2.cgPoint, to: cubicCurve.p3.cgPoint, offset: offset)
            } else if let quadraticCurve = curve as? QuadraticCurve {
                drawLine(context, from: quadraticCurve.p0.cgPoint, to: quadraticCurve.p1.cgPoint, offset: offset)
                drawLine(context, from: quadraticCurve.p1.cgPoint, to: quadraticCurve.p2.cgPoint, offset: offset)
            }

            if coords == true {
                context.setStrokeColor(black)
                drawPoints(context, points: curve.points.map(\.cgPoint), offset: offset)
            }
        }

        public static func drawHull(_ context: CGContext, hull: [CGPoint], offset _: CGPoint = .zero) {
            context.beginPath()
            if hull.count == 6 {
                context.move(to: hull[0])
                context.addLine(to: hull[1])
                context.addLine(to: hull[2])
                context.move(to: hull[3])
                context.addLine(to: hull[4])
            } else {
                context.move(to: hull[0])
                context.addLine(to: hull[1])
                context.addLine(to: hull[2])
                context.addLine(to: hull[3])
                context.move(to: hull[4])
                context.addLine(to: hull[5])
                context.addLine(to: hull[6])
                context.move(to: hull[7])
                context.addLine(to: hull[8])
            }
            context.strokePath()
        }

        public static func drawBoundingBox(_ context: CGContext, boundingBox: BoundingBox, offset: CGPoint = .zero) {
            context.beginPath()
            context.addRect(boundingBox.cgRect.offsetBy(dx: offset.x, dy: offset.y))
            context.closePath()
            context.strokePath()
        }

        public static func drawShape(_ context: CGContext, shape: Shape, offset: CGPoint = .zero) {
            @inline(__always) func addOffset(_ p: Point) -> CGPoint {
                CGPoint(x: p.x + offset.x, y: p.y + offset.y)
            }
            let order = shape.forward.points.count - 1
            context.beginPath()
            context.move(to: addOffset(shape.startcap.curve.startingPoint))
            context.addLine(to: addOffset(shape.startcap.curve.endingPoint))
            if order == 3 {
                context.addCurve(to: addOffset(shape.forward.points[3]),
                                 control1: addOffset(shape.forward.points[1]),
                                 control2: addOffset(shape.forward.points[2]))
            } else {
                context.addQuadCurve(to: addOffset(shape.forward.points[2]),
                                     control: addOffset(shape.forward.points[1]))
            }
            context.addLine(to: addOffset(shape.endcap.curve.endingPoint))
            if order == 3 {
                context.addCurve(to: addOffset(shape.back.points[3]),
                                 control1: addOffset(shape.back.points[1]),
                                 control2: addOffset(shape.back.points[2]))
            } else {
                context.addQuadCurve(to: addOffset(shape.back.points[2]),
                                     control: addOffset(shape.back.points[1]))
            }
            context.closePath()
            context.drawPath(using: .fillStroke)
        }

        public static func drawPathComponent(_ context: CGContext, pathComponent: PathComponent, offset: CGPoint = .zero, includeBoundingVolumeHierarchy: Bool = false) {
            if includeBoundingVolumeHierarchy {
                pathComponent.bvh.visit { node, depth in
                    setColor(context, color: randomColors[depth])
                    context.setLineWidth(1.0)
                    context.setLineWidth(5.0 / Double(depth + 1))
                    context.setAlpha(1.0 / Double(depth + 1))
                    drawBoundingBox(context, boundingBox: node.boundingBox, offset: offset)
                    return true // always visit children
                }
            }
            Draw.setRandomFill(context, alpha: 0.2)
            context.addPath(Path(components: [pathComponent]).cgPath)
            context.drawPath(using: .fillStroke)
        }

        public static func drawPath(_ context: CGContext, _ path: Path, offset _: CGPoint = .zero) {
            Draw.setRandomFill(context, alpha: 0.2)
            context.addPath(path.cgPath)
            context.drawPath(using: .fillStroke)
        }
    }

#endif

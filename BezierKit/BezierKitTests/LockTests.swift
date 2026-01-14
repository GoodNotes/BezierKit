//
//  LockTests.swift
//  MacDemos
//
//  Created by Holmes Futrell on 6/12/19.
//  Copyright © 2019 Holmes Futrell. All rights reserved.
//

@testable import BezierKit
import XCTest

#if !os(WASI)
    class LockTests: XCTestCase {
        func testPathPropertyAtomicity() {
            // ensure Path computed properties are thread-safe/deterministic
            let rect = Rect(x: 0, y: 0, width: 1, height: 1)
            let path = Path(rect: rect)

            let threadCount = 10000
            let expectation = XCTestExpectation()
            expectation.expectedFulfillmentCount = threadCount

            #if canImport(CoreGraphics)
                var cgPaths: [Int: CGPath] = [:]
            #endif
            var boundingBoxes: [Int: BoundingBox] = [:]

            for i in 0 ..< threadCount {
                let index = i
                DispatchQueue.global(qos: .default).async {
                    #if canImport(CoreGraphics)
                        let pathValue = path.cgPath
                    #endif
                    let boundingBoxValue = path.boundingBox
                    DispatchQueue.main.async {
                        #if canImport(CoreGraphics)
                            cgPaths[index] = pathValue
                        #endif
                        boundingBoxes[index] = boundingBoxValue
                        expectation.fulfill()
                    }
                }
            }
            wait(for: [expectation], timeout: 10.0)

            #if canImport(CoreGraphics)
                XCTAssertEqual(cgPaths.values.count, threadCount)
                let expected = Path(rect: rect).cgPath
                XCTAssertNotNil(cgPaths[0])
                XCTAssertTrue(cgPaths.values.allSatisfy { $0 == expected }, "cgPaths should all be structurally equal")
            #endif

            let expectedBoundingBox = Path(rect: rect).boundingBox
            XCTAssertEqual(boundingBoxes.values.count, threadCount)
            XCTAssertTrue(boundingBoxes.values.allSatisfy { $0 == expectedBoundingBox })
        }
    }
#endif

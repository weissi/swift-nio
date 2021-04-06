//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import XCTest
@testable import NIO

class CircularBufferTests: XCTestCase {
    func testTrivial() {
        var ring = CircularBuffer<Int>(initialCapacity: 8)
        ring.append(1)
        XCTAssertEqual(1, ring.removeFirst())
    }

    func testAddRemoveInALoop() {
        var ring = CircularBuffer<Int>(initialCapacity: 8)
        XCTAssertTrue(ring.isEmpty)
        XCTAssertEqual(0, ring.count)

        for f in 0..<1000 {
            ring.append(f)
            XCTAssertEqual(f, ring.removeFirst())
            XCTAssertTrue(ring.isEmpty)
            XCTAssertEqual(0, ring.count)
        }
    }

    func testAddAllRemoveAll() {
        var ring = CircularBuffer<Int>(initialCapacity: 8)
        XCTAssertTrue(ring.isEmpty)
        XCTAssertEqual(0, ring.count)

        for f in 1..<100 {
            ring.append(f)
            XCTAssertEqual(f, ring.count)
        }
        for f in 1..<100 {
            XCTAssertEqual(f, ring.removeFirst())
            XCTAssertEqual(99 - f, ring.count)
        }
        XCTAssertTrue(ring.isEmpty)
    }

    func testRemoveAt() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<7 {
            ring.prepend(idx)
        }

        XCTAssertEqual(7, ring.count)
        _ = ring.remove(at: ring.index(ring.startIndex, offsetBy: 1))
        XCTAssertEqual(6, ring.count)
        XCTAssertEqual(0, ring.last)
    }

    func testRemoveAtLastPosition() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<7 {
            ring.prepend(idx)
        }

        let last = ring.remove(at: ring.index(ring.endIndex, offsetBy: -1))
        XCTAssertEqual(0, last)
        XCTAssertEqual(1, ring.last)
    }

    func testRemoveAtTailIdx0() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        ring.prepend(99)
        ring.prepend(98)
        XCTAssertEqual(2, ring.count)
        XCTAssertEqual(99, ring.remove(at: ring.index(ring.endIndex, offsetBy: -1)))
        XCTAssertFalse(ring.isEmpty)
        XCTAssertEqual(1, ring.count)
        XCTAssertEqual(98, ring.last)
        XCTAssertEqual(98, ring.first)
    }

    func testRemoveAtFirstPosition() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<7 {
            ring.prepend(idx)
        }

        let first = ring.remove(at: ring.startIndex)
        XCTAssertEqual(6, first)
        XCTAssertEqual(5, ring.first)
    }

    func collectAllIndices<Element>(ring: CircularBuffer<Element>) -> [CircularBuffer<Element>.Index] {
        return Array(ring.indices)
    }

    func collectAllIndices<Element>(ring: CircularBuffer<Element>, range: Range<CircularBuffer<Element>.Index>) -> [CircularBuffer<Element>.Index] {
        var index: CircularBuffer<Element>.Index = range.lowerBound
        var allIndices: [CircularBuffer<Element>.Index] = []
        while index != range.upperBound {
            allIndices.append(index)
            index = ring.index(after: index)
        }
        return allIndices
    }

    func testHarderExpansion() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.startIndex))

        ring.append(1)
        XCTAssertEqual(ring.count, 1)
        XCTAssertEqual(ring[ring.startIndex], 1)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 1)))

        ring.append(2)
        XCTAssertEqual(ring.count, 2)
        XCTAssertEqual(ring[ring.startIndex], 1)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 1)], 2)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 2)))

        ring.append(3)
        XCTAssertEqual(ring.count, 3)
        XCTAssertEqual(ring[ring.startIndex], 1)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 1)], 2)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 2)], 3)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 3)))

        XCTAssertEqual(1, ring.removeFirst())
        XCTAssertEqual(ring.count, 2)
        XCTAssertEqual(ring[ring.startIndex], 2)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 1)], 3)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 2)))

        XCTAssertEqual(2, ring.removeFirst())
        XCTAssertEqual(ring.count, 1)
        XCTAssertEqual(ring[ring.startIndex], 3)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 1)))

        ring.append(5)
        XCTAssertEqual(ring.count, 2)
        XCTAssertEqual(ring[ring.startIndex], 3)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 1)], 5)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 2)))

        ring.append(6)
        XCTAssertEqual(ring.count, 3)
        XCTAssertEqual(ring[ring.startIndex], 3)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 1)], 5)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 2)], 6)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 3)))

        ring.append(7)
        XCTAssertEqual(ring.count, 4)
        XCTAssertEqual(ring[ring.startIndex], 3)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 1)], 5)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 2)], 6)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 3)], 7)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 4)))
    }

    func testCollection() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.startIndex))
        XCTAssertEqual(0, ring.distance(from: ring.startIndex, to: ring.endIndex))
        XCTAssertEqual(0, ring.distance(from: ring.startIndex, to: ring.startIndex))

        for idx in 0..<5 {
            ring.append(idx)
        }

        XCTAssertFalse(ring.isEmpty)
        XCTAssertEqual(5, ring.count)

        XCTAssertEqual(self.collectAllIndices(ring: ring),
                       self.collectAllIndices(ring: ring, range: ring.startIndex ..< ring.index(ring.startIndex,
                                                                                                offsetBy: 5)))
        XCTAssertEqual(ring.startIndex, ring.startIndex)
        XCTAssertEqual(ring.endIndex, ring.index(ring.startIndex, offsetBy: 5))

        XCTAssertEqual(ring.index(after: ring.index(ring.startIndex, offsetBy: 1)),
                       ring.index(ring.startIndex, offsetBy: 2))
        XCTAssertEqual(ring.index(before: ring.index(ring.startIndex, offsetBy: 3)),
                       ring.index(ring.startIndex, offsetBy: 2))
        
        let actualValues = [Int](ring)
        let expectedValues = [0, 1, 2, 3, 4]
        XCTAssertEqual(expectedValues, actualValues)
    }

    func testReplaceSubrange5ElementsWith1() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<50 {
            ring.prepend(idx)
        }
        XCTAssertEqual(50, ring.count)
        ring.replaceSubrange(ring.index(ring.startIndex, offsetBy: 20) ..< ring.index(ring.startIndex, offsetBy: 25),
                             with: [99])

        XCTAssertEqual(ring.count, 46)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 19)], 30)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 20)], 99)
        XCTAssertEqual(ring[ring.index(ring.startIndex, offsetBy: 21)], 24)
    }

    func testReplaceSubrangeAllElementsWithFewerElements() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<50 {
            ring.prepend(idx)
        }
        XCTAssertEqual(50, ring.count)

        ring.replaceSubrange(ring.startIndex..<ring.endIndex, with: [3,4])
        XCTAssertEqual(2, ring.count)
        XCTAssertEqual(3, ring.first)
        XCTAssertEqual(4, ring.last)
    }

    func testReplaceSubrangeEmptyRange() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<50 {
            ring.prepend(idx)
        }
        XCTAssertEqual(50, ring.count)

        ring.replaceSubrange(ring.startIndex ..< ring.startIndex, with: [])
        XCTAssertEqual(50, ring.count)
    }

    func testReplaceSubrangeWithSubrangeLargerThanTargetRange() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<5 {
            ring.prepend(idx)
        }
        XCTAssertEqual(5, ring.count)

        ring.replaceSubrange(ring.startIndex..<ring.endIndex, with: [10,11,12,13,14,15,16,17,18,19])
        XCTAssertEqual(10, ring.count)
        XCTAssertEqual(10, ring.first)
        XCTAssertEqual(19, ring.last)
    }

    func testReplaceSubrangeSameSize() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<5 {
            ring.prepend(idx)
        }
        XCTAssertEqual(5, ring.count)
        XCTAssertEqual(4, ring.first)
        XCTAssertEqual(0, ring.last)

        var replacement = [Int]()
        for idx in 0..<5 {
            replacement.append(idx)
        }
        XCTAssertEqual(5, replacement.count)
        XCTAssertEqual(0, replacement.first)
        XCTAssertEqual(4, replacement.last)

        ring.replaceSubrange(ring.startIndex..<ring.endIndex, with: replacement)
        XCTAssertEqual(5, ring.count)
        XCTAssertEqual(0, ring.first)
        XCTAssertEqual(4, ring.last)
    }

    func testReplaceSubrangeReplaceBufferWithEmptyArray() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<5 {
            ring.prepend(idx)
        }
        XCTAssertEqual(5, ring.count)
        XCTAssertEqual(4, ring.first)
        XCTAssertEqual(0, ring.last)

        ring.replaceSubrange(ring.startIndex..<ring.endIndex, with: [])
        XCTAssertTrue(ring.isEmpty)
    }

    func testWeCanDistinguishBetweenEmptyAndFull() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        XCTAssertTrue(ring.isEmpty)
        for idx in 0..<4 {
            ring.append(idx)
        }
        XCTAssertEqual(4, ring.count)
        XCTAssertFalse(ring.isEmpty)
    }

    func testExpandZeroBasedRingWorks() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<5 {
            ring.append(idx)
        }
        for idx in 0..<5 {
            XCTAssertEqual(idx, ring[ring.index(ring.startIndex, offsetBy: idx)])
        }
    }

    func testExpandNonZeroBasedRingWorks() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        for idx in 0..<4 {
            ring.append(idx)
        }
        /* the underlying buffer should now be filled from 0 to max */
        for idx in 0..<4 {
            XCTAssertEqual(idx, ring[ring.index(ring.startIndex, offsetBy: idx)])
        }
        XCTAssertEqual(0, ring.removeFirst())
        /* now the first element is gone, ie. the ring starts at index 1 now */
        for idx in 0..<3 {
            XCTAssertEqual(idx + 1, ring[ring.index(ring.startIndex, offsetBy: idx)])
        }
        ring.append(4)
        XCTAssertEqual(1, ring.first!)
        /* now the last element should be at ring position 0 */
        for idx in 0..<4 {
            XCTAssertEqual(idx + 1, ring[ring.index(ring.startIndex, offsetBy: idx)])
        }
        /* and now we'll make it expand */
        ring.append(5)
        for idx in 0..<5 {
            XCTAssertEqual(idx + 1, ring[ring.index(ring.startIndex, offsetBy: idx)])
        }
    }

    func testEmptyingExpandedRingWorks() {
        var ring = CircularBuffer<Int>(initialCapacity: 2)
        for idx in 0..<4 {
            ring.append(idx)
        }
        for idx in 0..<4 {
            XCTAssertEqual(idx, ring[ring.index(ring.startIndex, offsetBy: idx)])
        }
        for idx in 0..<4 {
            XCTAssertEqual(idx, ring.removeFirst())
        }
        XCTAssertTrue(ring.isEmpty)
        XCTAssertNil(ring.first)
    }

    func testChangeElements() {
        var ring = CircularBuffer<Int>(initialCapacity: 100)
        for idx in 0..<50 {
            ring.append(idx)
        }
        var changes: [(Int, Int)] = []
        for (idx, element) in ring.enumerated() {
            XCTAssertEqual(idx, element)
            changes.append((idx, element * 2))
        }
        for change in changes {
            ring[ring.index(ring.startIndex, offsetBy: change.0)] = change.1
        }
        for (idx, element) in ring.enumerated() {
            XCTAssertEqual(idx * 2, element)
        }
    }

    func testSliceTheRing() {
        var ring = CircularBuffer<Int>(initialCapacity: 100)
        for idx in 0..<50 {
            ring.append(idx)
        }

        let slice = ring[ring.index(ring.startIndex, offsetBy: 25) ..< ring.index(ring.startIndex, offsetBy: 30)]
        for (idx, element) in slice.enumerated() {
            XCTAssertEqual(ring.index(ring.startIndex, offsetBy: idx + 25),
                           ring.index(ring.startIndex, offsetBy: element))
        }
    }

    func testCount() {
        var ring = CircularBuffer<Int>(initialCapacity: 4)
        ring.append(1)
        XCTAssertEqual(1, ring.count)
        ring.append(2)
        XCTAssertEqual(2, ring.count)
        XCTAssertEqual(1, ring.removeFirst())
        ring.append(3)
        XCTAssertEqual(2, ring.count)
        XCTAssertEqual(2, ring.removeFirst())
        ring.append(4)

        XCTAssertEqual(2, ring.count)
        XCTAssertEqual(3, ring.removeFirst())
        ring.append(5)

        XCTAssertEqual(2, ring.count)
        XCTAssertEqual(4, ring.removeFirst())
        XCTAssertEqual(5, ring.removeFirst())
        XCTAssertEqual(0, ring.count)
        XCTAssertTrue(ring.isEmpty)
    }

    func testFirst() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        XCTAssertNil(ring.first)
        ring.append(1)
        XCTAssertEqual(1, ring.first)
        XCTAssertEqual(1, ring.removeFirst())
        XCTAssertNil(ring.first)
    }

    func testLast() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        XCTAssertNil(ring.last)
        ring.prepend(1)
        XCTAssertEqual(1, ring.last)
        XCTAssertEqual(1, ring.removeLast())
        XCTAssertNil(ring.last)
        XCTAssertEqual(0, ring.count)
        XCTAssertTrue(ring.isEmpty)
    }

    func testRemoveLast() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        XCTAssertNil(ring.last)
        ring.append(1)
        ring.prepend(0)
        XCTAssertEqual(1, ring.last)
        XCTAssertEqual(1, ring.removeLast())
        XCTAssertEqual(0, ring.last)
    }

    func testRemoveLastCountElements() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        XCTAssertNil(ring.last)
        ring.append(1)
        ring.prepend(0)
        XCTAssertEqual(1, ring.last)
        ring.removeLast(2)
        XCTAssertTrue(ring.isEmpty)
    }

    func testRemoveLastElements() {
        var ring = CircularBuffer<Int>(initialCapacity: 10)
        XCTAssertNil(ring.last)
        for i in 0 ..< 20 {
            ring.prepend(i)
        }
        XCTAssertEqual(20, ring.count)
        XCTAssertEqual(19, ring.first)
        XCTAssertEqual(0, ring.last)
        ring.removeLast(10)
        XCTAssertEqual(10, ring.count)
        XCTAssertEqual(19, ring.first)
        XCTAssertEqual(10, ring.last)
    }
    
    func testOperateOnBothSides() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        XCTAssertNil(ring.last)
        ring.prepend(1)
        ring.prepend(2)

        XCTAssertEqual(1, ring.last)
        XCTAssertEqual(2, ring.first)

        XCTAssertEqual(1, ring.removeLast())
        XCTAssertEqual(2, ring.removeFirst())

        XCTAssertNil(ring.last)
        XCTAssertNil(ring.first)
        XCTAssertEqual(0, ring.count)
        XCTAssertTrue(ring.isEmpty)
    }

    func testPrependExpandBuffer() {
        var ring = CircularBuffer<Int>(initialCapacity: 3)
        for f in 1..<1000 {
            ring.prepend(f)
            XCTAssertEqual(f, ring.count)
        }
        for f in 1..<1000 {
            XCTAssertEqual(f, ring.removeLast())
        }
        XCTAssertTrue(ring.isEmpty)
        XCTAssertEqual(0, ring.count)
    }

    func testRemoveAllKeepingCapacity() {
        var ring = CircularBuffer<Int>(initialCapacity: 2)
        ring.append(1)
        ring.append(2)
        XCTAssertEqual(ring.count, 2)
        ring.removeAll(keepingCapacity: true)
        XCTAssertEqual(ring.count, 0)
    }

    func testRemoveAllNotKeepingCapacity() {
        var ring = CircularBuffer<Int>(initialCapacity: 2)
        ring.append(1)
        ring.append(2)
        XCTAssertEqual(ring.count, 2)
        ring.removeAll(keepingCapacity: false)
        XCTAssertEqual(ring.count, 0)
        ring.append(1)
        XCTAssertEqual(ring.count, 1)
        ring.append(2)
        XCTAssertEqual(ring.count, 2)
        ring.removeAll() // default should not keep capacity
        XCTAssertEqual(ring.count, 0)
    }

    func testBufferManaged() {
        var ring = CircularBuffer<Int>(initialCapacity: 2)
        ring.append(1)

        // Now we want to replace the last subrange with two elements. This should
        // force an increase in size.
        ring.replaceSubrange(ring.startIndex ..< ring.index(ring.startIndex, offsetBy: 1), with: [3, 4])

        XCTAssertEqual([3, 4], Array(ring))
    }

    func testExpandRemoveAllKeepingAndNotKeepingCapacityAndExpandAgain() {
        for shouldKeepCapacity in [false, true] {
            var ring = CircularBuffer<Int>(initialCapacity: 4)

            (0..<16).forEach { ring.append($0) }
            (0..<4).forEach { _ in _ = ring.removeFirst() }
            (16..<20).forEach { ring.append($0) }
            XCTAssertEqual(Array(4..<20), Array(ring))

            ring.removeAll(keepingCapacity: shouldKeepCapacity)

            (0..<8).forEach { ring.append($0) }
            (0..<4).forEach { _ in _ = ring.removeFirst() }
            (8..<64).forEach { ring.append($0) }

            XCTAssertEqual(Array(4..<64), Array(ring))
        }
    }

    func testRemoveAllNilsOutTheContents() {
        class Dummy {}

        weak var dummy1: Dummy? = nil
        weak var dummy2: Dummy? = nil
        weak var dummy3: Dummy? = nil
        weak var dummy4: Dummy? = nil
        weak var dummy5: Dummy? = nil
        weak var dummy6: Dummy? = nil
        weak var dummy7: Dummy? = nil
        weak var dummy8: Dummy? = nil

        var ring: CircularBuffer<Dummy> = .init(initialCapacity: 4)

        ({
            for _ in 0..<2 {
                ring.append(Dummy())
            }

            dummy1 = ring.dropFirst(0).first
            dummy2 = ring.dropFirst(1).first

            XCTAssertNotNil(dummy1)
            XCTAssertNotNil(dummy2)

            _ = ring.removeFirst()

            for _ in 2..<8 {
                ring.append(Dummy())
            }

            dummy3 = ring.dropFirst(1).first
            dummy4 = ring.dropFirst(2).first
            dummy5 = ring.dropFirst(3).first
            dummy6 = ring.dropFirst(4).first
            dummy7 = ring.dropFirst(5).first
            dummy8 = ring.dropFirst(6).first

            XCTAssertNotNil(dummy3)
            XCTAssertNotNil(dummy4)
            XCTAssertNotNil(dummy5)
            XCTAssertNotNil(dummy6)
            XCTAssertNotNil(dummy7)
            XCTAssertNotNil(dummy8)
        })()

        XCTAssertNotNil(dummy2)
        XCTAssertNotNil(dummy3)
        XCTAssertNotNil(dummy4)
        XCTAssertNotNil(dummy5)
        XCTAssertNotNil(dummy6)
        XCTAssertNotNil(dummy7)
        XCTAssertNotNil(dummy8)

        ring.removeAll(keepingCapacity: true)

        assert(dummy1 == nil, within: .seconds(1))
        assert(dummy2 == nil, within: .seconds(1))
        assert(dummy3 == nil, within: .seconds(1))
        assert(dummy4 == nil, within: .seconds(1))
        assert(dummy5 == nil, within: .seconds(1))
        assert(dummy6 == nil, within: .seconds(1))
        assert(dummy7 == nil, within: .seconds(1))
        assert(dummy8 == nil, within: .seconds(1))
    }
    
    func testIntIndexing() {
        var ring = CircularBuffer<Int>()
        for i in 0 ..< 5 {
            ring.append(i)
            XCTAssertEqual(ring[offset: i], i)
        }
        
        XCTAssertEqual(ring[ring.startIndex], ring[offset :0])
        XCTAssertEqual(ring[ring.index(before: ring.endIndex)], ring[offset: 4])
        
        ring[offset: 1] = 10
        XCTAssertEqual(ring[ring.index(after: ring.startIndex)], 10)
    }

    func testPopFirst() {
        var buf = CircularBuffer([1, 2, 3])
        if let element = buf.popFirst() {
            XCTAssertEqual(1, element)
        } else {
            XCTFail("popFirst didn't find first element")
        }
        
        if let element = buf.popFirst() {
            XCTAssertEqual(2, element)
        } else {
            XCTFail("popFirst didn't find second element")
        }

        if let element = buf.popFirst() {
            XCTAssertEqual(3, element)
        } else {
            XCTFail("popFirst didn't find third element")
        }
        
        XCTAssertNil(buf.popFirst())
    }
    
    func testRemoveInMiddle() {
        var buf = CircularBuffer<Int>(initialCapacity: 8)
        for i in 0..<7 {
            buf.append(i)
        }
        XCTAssertEqual(0, buf.removeFirst())
        buf.append(7)
        XCTAssertEqual(2, buf.remove(at: buf.index(buf.startIndex, offsetBy: 1)))
        XCTAssertEqual([1, 3, 4, 5, 6, 7], Array(buf))
        buf.removeAll(keepingCapacity: true)
        XCTAssertEqual([], Array(buf))
    }

    func testLotsOfPrepending() {
        var buf = CircularBuffer<Int>(initialCapacity: 8)

        for i in (0..<128).reversed() {
            buf.prepend(i)
        }
        XCTAssertEqual(Array(0..<128), Array(buf))
    }

    func testLotsOfInsertAtStart() {
        var buf = CircularBuffer<Int>(initialCapacity: 8)

        for i in (0..<128).reversed() {
            buf.insert(i, at: buf.startIndex)
        }
        XCTAssertEqual(Array(0..<128), Array(buf))
    }

    func testLotsOfInsertAtEnd() {
        var buf = CircularBuffer<Int>(initialCapacity: 8)

        for i in (0..<128) {
            buf.insert(i, at: buf.endIndex)
        }
        XCTAssertEqual(Array(0..<128), Array(buf))
    }

    func testPopLast() {
        var buf = CircularBuffer<Int>(initialCapacity: 4)
        buf.append(1)
        XCTAssertEqual(1, buf.popLast())
        XCTAssertNil(buf.popLast())

        buf.append(1)
        buf.append(2)
        buf.append(3)
        XCTAssertEqual(3, buf.popLast())
        XCTAssertEqual(2, buf.popLast())
        XCTAssertEqual(1, buf.popLast())
        XCTAssertNil(buf.popLast())
    }

    func testModify() {
        var buf = CircularBuffer<Int>(initialCapacity: 4)
        buf.append(contentsOf: 0..<4)
        XCTAssertEqual(Array(0..<4), Array(buf))

        let secondIndex = buf.index(after: buf.startIndex)
        buf.modify(secondIndex) { value in
            XCTAssertEqual(value, 1)
            value = 5
        }
        XCTAssertEqual([0, 5, 2, 3], Array(buf))
    }
    
    func testEquality() {
        // Empty buffers
        let emptyA = CircularBuffer<Int>()
        let emptyB = CircularBuffer<Int>()
        XCTAssertEqual(emptyA, emptyB)
        
        var buffA = CircularBuffer<Int>()
        var buffB = CircularBuffer<Int>()
        var buffC = CircularBuffer<Int>()
        var buffD = CircularBuffer<Int>()
        buffA.append(contentsOf: 1...10)
        buffB.append(contentsOf: 1...10)
        buffC.append(contentsOf: 2...11) // Same count different values
        buffD.append(contentsOf: 1...2) // Different count
        XCTAssertEqual(buffA, buffB)
        XCTAssertNotEqual(buffA, buffC)
        XCTAssertNotEqual(buffA, buffD)
        
        // Will make internal head/tail indexes different
        var prependBuff = CircularBuffer<Int>()
        var appendBuff = CircularBuffer<Int>()
        for i in (1...100).reversed() {
            prependBuff.prepend(i)
        }
        for i in 1...100 {
            appendBuff.append(i)
        }
        // But the contents are still the same
        XCTAssertEqual(prependBuff, appendBuff)
    }
    
    func testHash() {
        let emptyA = CircularBuffer<Int>()
        let emptyB = CircularBuffer<Int>()
        XCTAssertEqual(Set([emptyA,emptyB]).count, 1)
        
        var buffA = CircularBuffer<Int>()
        var buffB = CircularBuffer<Int>()
        buffA.append(contentsOf: 1...10)
        buffB.append(contentsOf: 1...10)
        XCTAssertEqual(Set([buffA,buffB]).count, 1)
        buffB.append(123)
        XCTAssertEqual(Set([buffA,buffB]).count, 2)
        buffA.append(1)
        XCTAssertEqual(Set([buffA,buffB]).count, 2)
        
        // Will make internal head/tail indexes different
        var prependBuff = CircularBuffer<Int>()
        var appendBuff = CircularBuffer<Int>()
        for i in (1...100).reversed() {
            prependBuff.prepend(i)
        }
        for i in 1...100 {
            appendBuff.append(i)
        }
        XCTAssertEqual(Set([prependBuff,appendBuff]).count, 1)
    }
    
    func testArrayLiteralInit() {
        let empty: CircularBuffer<Int> = []
        XCTAssert(empty.isEmpty)
        
        let increasingInts: CircularBuffer = [1, 2, 3, 4, 5]
        XCTAssertEqual(increasingInts.count, 5)
        XCTAssert(zip(increasingInts, 1...5).allSatisfy(==))
        
        let someIntsArray = [-9, 384, 2, 10, 0, 0, 0]
        let someInts: CircularBuffer = [-9, 384, 2, 10, 0, 0, 0]
        XCTAssertEqual(someInts.count, 7)
        XCTAssert(zip(someInts, someIntsArray).allSatisfy(==))
    }
}

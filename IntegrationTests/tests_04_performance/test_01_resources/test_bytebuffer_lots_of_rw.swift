//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import NIO
import NIOFoundationCompat

func run(identifier: String) {
    measure(identifier: identifier) {
        let dispatchData = ("A" as StaticString).withUTF8Buffer { ptr in
            DispatchData(bytes: UnsafeRawBufferPointer(ptr))
        }
        var buffer = ByteBufferAllocator().buffer(capacity: 7 * 1000)
        let foundationData = "A".data(using: .utf8)!
        @inline(never)
        func doWrites(buffer: inout ByteBuffer) {
            /* these ones are zero allocations */
            buffer.writeBytes([0x41])
            buffer.writeBytes("A".utf8)
            buffer.writeString("A")
            buffer.writeStaticString("A")
            buffer.writeInteger(0x41, as: UInt8.self)
            buffer.writeRepeatingByte(0x41, count: 16)

            /* those down here should be one allocation each (on Linux) */
            buffer.writeBytes(dispatchData) // see https://bugs.swift.org/browse/SR-9597
        }
        @inline(never)
        func doReads(buffer: inout ByteBuffer) {
            /* these ones are zero allocations */
            var val = buffer.readInteger(as: UInt8.self)
            precondition(0x41 == val, "\(val!)")
            val = buffer.readInteger(as: UInt16.self)
            precondition(0x4141 == val, "\(val!)")
            var slice = buffer.readSlice(length: 1)
            let sliceVal = slice!.readInteger(as: UInt8.self)
            precondition(0x41 == sliceVal, "\(sliceVal!)")
            buffer.withUnsafeReadableBytes { ptr in
                precondition(ptr[0] == 0x41)
            }
            let str = buffer.readString(length: 1)
            precondition("A" == str, "\(str!)")

            /* those down here should be one allocation each */
            let arr = buffer.readBytes(length: 1)
            precondition([0x41] == arr!, "\(arr!)")
            let data = buffer.readData(length: 16, byteTransferStrategy: .noCopy)
            precondition(0x41 == data?.first && 0x41 == data?.last)
        }
        for _ in 0..<1000  {
            doWrites(buffer: &buffer)
            doReads(buffer: &buffer)
            precondition(buffer.readableBytes == 0)
        }
        return buffer.readableBytes
    }
}

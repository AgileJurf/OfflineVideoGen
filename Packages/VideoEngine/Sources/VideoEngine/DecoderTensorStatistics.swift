import CoreML
import Foundation

/// Checks actual tensor elements without copying a potentially large decoder buffer.
/// Padding is skipped using the declared strides; no tensor contents leave the device.
struct DecoderTensorStatistics {
    let shape: [Int]
    let strides: [Int]
    let scalarCount: Int
    let nonFiniteCount: Int
    let zeroCount: Int
    let minimum: Float32?
    let maximum: Float32?

    init(_ array: MLShapedArray<Float32>) throws {
        self = try array.withUnsafeShapedBufferPointer { buffer, shape, strides in
            guard shape.count == strides.count, !shape.isEmpty,
                  shape.allSatisfy({ $0 > 0 }), strides.allSatisfy({ $0 >= 0 }) else {
                throw GenerationError.invalidTensor
            }
            let count = shape.reduce(1, *)
            let lastOffset = zip(shape, strides).reduce(0) { $0 + ($1.0 - 1) * $1.1 }
            guard lastOffset < buffer.count else { throw GenerationError.invalidTensor }
            var expectedStride = 1
            var contiguous = true
            for axis in shape.indices.reversed() {
                if shape[axis] > 1 && strides[axis] != expectedStride { contiguous = false }
                expectedStride *= shape[axis]
            }
            var nonFinite = 0, zeros = 0
            var low: Float32?, high: Float32?
            func consume(_ value: Float32) {
                guard value.isFinite else { nonFinite += 1; return }
                if value == 0 { zeros += 1 }
                low = low.map { min($0, value) } ?? value
                high = high.map { max($0, value) } ?? value
            }
            if contiguous {
                for offset in 0..<count { consume(buffer[offset]) }
            } else {
                func visit(_ axis: Int, _ offset: Int) {
                    if axis == shape.count { consume(buffer[offset]); return }
                    for index in 0..<shape[axis] { visit(axis + 1, offset + index * strides[axis]) }
                }
                visit(0, 0)
            }
            return Self(shape: shape, strides: strides, scalarCount: count,
                        nonFiniteCount: nonFinite, zeroCount: zeros, minimum: low, maximum: high)
        }
    }

    private init(shape: [Int], strides: [Int], scalarCount: Int, nonFiniteCount: Int,
                 zeroCount: Int, minimum: Float32?, maximum: Float32?) {
        self.shape = shape; self.strides = strides; self.scalarCount = scalarCount
        self.nonFiniteCount = nonFiniteCount; self.zeroCount = zeroCount
        self.minimum = minimum; self.maximum = maximum
    }

    var fields: [String: String] {
        ["shape": String(describing: shape), "strides": String(describing: strides),
         "scalarCount": String(scalarCount), "nonFiniteCount": String(nonFiniteCount),
         "zeroCount": String(zeroCount), "minimum": minimum.map { String($0) } ?? "none",
         "maximum": maximum.map { String($0) } ?? "none"]
    }

    func requireFinite() throws {
        guard nonFiniteCount == 0 else { throw GenerationError.invalidTensor }
    }
}

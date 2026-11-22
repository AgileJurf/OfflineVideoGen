import Foundation

/// Small CPU-side latent operations. These do not modify trained weights.
/// Layout is contiguous C,H,W for one latent frame.
struct NeodragonGrid {
    let values: [Float32]
    let height: Int
    let width: Int
    var channels: Int { values.count / (height * width) }

    func downsample(variancePreserving: Bool = false) -> NeodragonGrid {
        precondition(height.isMultiple(of: 2) && width.isMultiple(of: 2))
        let h = height / 2, w = width / 2
        var result = [Float32](repeating: 0, count: channels * h * w)
        for channel in 0..<channels {
            for y in 0..<h {
                for x in 0..<w {
                    let index = channel * height * width + y * 2 * width + x * 2
                    let upper = values[index] * 0.5 + values[index + 1] * 0.5
                    let lower = values[index + width] * 0.5 + values[index + width + 1] * 0.5
                    let average = upper * 0.5 + lower * 0.5
                    result[channel * h * w + y * w + x] = variancePreserving ? average * 2 : average
                }
            }
        }
        return .init(values: result, height: h, width: w)
    }

    var pyramid: [NeodragonGrid] {
        let middle = downsample()
        return [middle.downsample(), middle, self]
    }

    func nearestUpsample() -> NeodragonGrid {
        let h = height * 2, w = width * 2
        var result = [Float32](repeating: 0, count: channels * h * w)
        for channel in 0..<channels {
            for y in 0..<h {
                for x in 0..<w {
                    result[channel * h * w + y * w + x] = values[channel * height * width + (y / 2) * width + x / 2]
                }
            }
        }
        return .init(values: result, height: h, width: w)
    }
}

/// Deterministic native random stream. Seeds reproduce native runs; they do not
/// imply the same random trajectory as PyTorch's different generator.
struct NeodragonRandom {
    private var state: UInt64
    private var spare: Float32?
    init(seed: UInt64) { state = seed }

    private mutating func uniform() -> Double {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        value ^= value >> 31
        return (Double(value >> 11) + 0.5) / 9_007_199_254_740_992
    }

    mutating func normal() -> Float32 {
        if let spare { self.spare = nil; return spare }
        let radius = sqrt(-2 * log(uniform()))
        let angle = 2 * Double.pi * uniform()
        spare = Float32(radius * sin(angle))
        return Float32(radius * cos(angle))
    }

    mutating func normals(count: Int) -> [Float32] {
        (0..<count).map { _ in normal() }
    }
}

struct NeodragonAttentionLayout {
    let lengths: [Int]
    let mask: [Float32]
    let cosine: [Float32]
    let sine: [Float32]
    var imageTokens: Int { lengths.reduce(0, +) }
    var totalTokens: Int { imageTokens + 128 }

    init(lengths: [Int], textTokenCount: Int) {
        precondition((1...128).contains(textTokenCount) && !lengths.isEmpty && lengths.allSatisfy { $0 > 0 })
        self.lengths = lengths
        let positions = Array(repeating: 0, count: 128) + lengths.enumerated().flatMap { Array(repeating: $0.offset, count: $0.element) }
        let allowed = (0..<positions.count).map { $0 < textTokenCount || $0 >= 128 }
        var mask = [Float32](repeating: 0, count: positions.count * positions.count)
        var cosine = [Float32](repeating: 0, count: positions.count * 32)
        var sine = cosine
        let frequency = (0..<32).map { 1 / pow(10_000.0, Double($0 * 2) / 64) }
        for query in positions.indices {
            for key in positions.indices where allowed[query] == allowed[key] && positions[query] >= positions[key] {
                mask[query * positions.count + key] = 1
            }
            for dimension in 0..<32 {
                let angle = Double(positions[query]) * frequency[dimension]
                cosine[query * 32 + dimension] = Float32(cos(angle))
                sine[query * 32 + dimension] = Float32(sin(angle))
            }
        }
        self.mask = mask; self.cosine = cosine; self.sine = sine
    }
}

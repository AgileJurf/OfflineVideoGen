import Foundation

/// The first-image bridge uses the same byte rounding and separable Lanczos
/// sampling as the upstream diffusers → Pillow → video-VAE path. This is model
/// input preparation, not an animation or video-generation substitute.
enum NeodragonImageProcessing {
    static func imageBytes(_ values: [Float32]) throws -> [UInt8] {
        guard values.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        return values.map { value in
            let normalized = min(max(value * 0.5 + 0.5, 0), 1)
            return UInt8((normalized * 255).rounded(.toNearestOrEven))
        }
    }

    static func videoInput(decoded: [Float32]) throws -> [Float32] {
        guard decoded.count == 3 * 640 * 1024 else { throw GenerationError.invalidTensor }
        let pixels = try downsampleRGB(imageBytes(decoded), width: 1024, height: 640)
        return pixels.map { Float32($0) / 255 * 2 - 1 }
    }

    /// Planar RGB, fixed 2× downsample. Coefficient quantization and intermediate
    /// byte clipping follow Pillow's 8-bit Lanczos path (see bundled notice).
    static func downsampleRGB(_ values: [UInt8], width: Int, height: Int) throws -> [UInt8] {
        guard width > 0, height > 0, width <= 1024, height <= 640,
              width.isMultiple(of: 2), height.isMultiple(of: 2), values.count == 3 * width * height else {
            throw GenerationError.invalidTensor
        }
        let columns = coefficients(input: width), rows = coefficients(input: height)
        let outWidth = width / 2, outHeight = height / 2
        var horizontal = [UInt8](repeating: 0, count: 3 * outWidth * height)
        var result = [UInt8](repeating: 0, count: 3 * outWidth * outHeight)
        for channel in 0..<3 {
            for y in 0..<height {
                for x in 0..<outWidth {
                    let filter = columns[x]
                    var sum = 1 << 21
                    for (tap, coefficient) in filter.weights.enumerated() {
                        sum += Int(values[(channel * height + y) * width + filter.start + tap]) * coefficient
                    }
                    horizontal[(channel * height + y) * outWidth + x] = UInt8(clamping: sum >> 22)
                }
            }
            for y in 0..<outHeight {
                let filter = rows[y]
                for x in 0..<outWidth {
                    var sum = 1 << 21
                    for (tap, coefficient) in filter.weights.enumerated() {
                        sum += Int(horizontal[(channel * height + filter.start + tap) * outWidth + x]) * coefficient
                    }
                    result[(channel * outHeight + y) * outWidth + x] = UInt8(clamping: sum >> 22)
                }
            }
        }
        return result
    }

    private static func coefficients(input: Int) -> [(start: Int, weights: [Int])] {
        func sinc(_ value: Double) -> Double { value == 0 ? 1 : sin(value * .pi) / (value * .pi) }
        return (0..<(input / 2)).map { output in
            let center = (Double(output) + 0.5) * 2
            let start = max(0, Int(center - 6 + 0.5)), end = min(input, Int(center + 6 + 0.5))
            let raw = (start..<end).map { source -> Double in
                let position = (Double(source) - center + 0.5) / 2
                return position >= -3 && position < 3 ? sinc(position) * sinc(position / 3) : 0
            }
            let total = raw.reduce(0, +)
            let weights = raw.map { Int(($0 / total * Double(1 << 22)).rounded(.toNearestOrAwayFromZero)) }
            return (start, weights)
        }
    }
}

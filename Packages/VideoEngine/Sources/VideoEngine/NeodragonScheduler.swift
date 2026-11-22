import Foundation

/// The published Neodragon hybrid profile. It is not an approved device preset.
/// Its first frame uses SSD-1B; six subsequent latent units use three flow stages.
public enum NeodragonModel {
    public static let identifier = "neodragon-hybrid-v1"
    public static let weightsRevision = "5bdc87a4895a4fd148ca14c03181345d278d1040"
    public static let sourceRevision = "d2abbe99f46577c4e1db682ad3c26832ec0c23b9"
    public static let width = 512
    public static let height = 320
    public static let framesPerSecond = 24
    public static let frameCount = 49
    public static let latentFrames = 7
    public static let channels = 16
    public static let decoderNames = (0..<4).map { "decoder_stage_\($0)" }
    public static var licenseNotices: String {
        guard let url = Bundle.module.url(forResource: "Neodragon-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Model license notices are unavailable in this build." }
        return text
    }

    /// Source-compatible frame geometry, not a claim of validated device support.
    /// Causal decoding yields 8n + 1 frames. Export keeps the requested prefix.
    public static func geometry(seconds: Int) throws -> (latentFrames: Int, nativeFrames: Int, exportFrames: Int) {
        guard (2...9).contains(seconds) else { throw GenerationError.incompatibleModel("Neodragon duration must be 2–9 seconds") }
        let count = seconds * framesPerSecond
        let latents = (count - 1 + 7) / 8 + 1
        return (latents, (latents - 1) * 8 + 1, count)
    }
}

/// Port of the upstream PyramidFlowMatchEulerDiscreteScheduler's three-stage,
/// one-evaluation-per-stage configuration. MOVD's scheduler is unaffected.
/// Qualcomm BSD-3-Clause-Clear notice is bundled in Neodragon-LICENSE.txt.
struct NeodragonScheduler {
    struct Stage {
        let timestep: Float32
        let originalStartSigma: Float32
        let correctedStartSigma: Double
        let endSigma: Float32
        let upsampleSignal: Float32
        let upsampleNoise: Float32
    }
    let stages: [Stage]

    init() {
        // NumPy/torch start from Float32 timesteps, then use Double for the
        // correction and range ratios. Keep that order to match stage boundaries.
        let starts: [Float32] = [1, Float32(667) / 1000, Float32(334) / 1000]
        let ends: [Float32] = [starts[1], starts[2], 0]
        let corrected = starts.enumerated().map { index, sigma -> Double in
            if index == 0 { return 1 }
            let original = Double(sigma)
            return 1 - (1 - original) / (2 * original + (1 - original))
        }
        let distances = zip(corrected, ends).map { $0 - Double($1) }
        let total = distances.reduce(0, +)
        stages = starts.indices.map { index in
            let startRatio = distances.prefix(index).reduce(0, +) / total
            let timestep = Float32(1000 - Int(startRatio * 1000))
            let signal = 1 / (2 * Double(starts[index]) + (1 - Double(starts[index])))
            let noise = signal * Double(starts[index]) / sqrt(1.0 / 3.0)
            return Stage(timestep: timestep, originalStartSigma: starts[index],
                         correctedStartSigma: corrected[index], endSigma: ends[index],
                         upsampleSignal: Float32(signal), upsampleNoise: Float32(noise))
        }
    }

    /// The distilled schedule uses local sigma 1 → 0 in every stage.
    func step(sample: [Float32], predictedFlow: [Float32]) throws -> [Float32] {
        guard !sample.isEmpty, sample.count == predictedFlow.count,
              sample.allSatisfy(\.isFinite), predictedFlow.allSatisfy(\.isFinite) else {
            throw GenerationError.invalidTensor
        }
        let result = zip(sample, predictedFlow).map(-)
        guard result.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        return result
    }
}

import Foundation

/// Published four-step SSD-1B LCM schedule. Coefficients and test vectors come
/// from diffusers, independently recorded in fixtures/lcm-parity.json.
struct NeodragonImageScheduler {
    struct Step {
        let timestep: Float32
        let alpha: Float32
        let previousAlpha: Float32
        let skip: Float32
    }
    let steps: [Step] = [
        .init(timestep: 999, alpha: 0.00466009508818388, previousAlpha: 0.05662344768643379, skip: 2.505007534736592e-09),
        .init(timestep: 749, alpha: 0.05662344768643379, previousAlpha: 0.27766942977905273, skip: 4.456320201740027e-09),
        .init(timestep: 499, alpha: 0.27766942977905273, previousAlpha: 0.6754320859909058, skip: 1.0040120734799984e-08),
        .init(timestep: 249, alpha: 0.6754320859909058, previousAlpha: 0.6754320859909058, skip: 4.032192890690567e-08)
    ]

    func advance(index: Int, sample: [Float32], prediction: [Float32], noise: [Float32]) throws -> [Float32] {
        guard steps.indices.contains(index), !sample.isEmpty, sample.count == prediction.count,
              noise.count == sample.count, sample.allSatisfy(\.isFinite),
              prediction.allSatisfy(\.isFinite), noise.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        let step = steps[index]
        let signal = sqrt(step.alpha), deviation = sqrt(1 - step.alpha)
        let previousSignal = sqrt(step.previousAlpha), previousDeviation = sqrt(1 - step.previousAlpha)
        let result = sample.indices.map { i -> Float32 in
            let original = (sample[i] - deviation * prediction[i]) / signal
            // c_out rounds to exactly 1.0 at all four published timesteps.
            let denoised = original + step.skip * sample[i]
            return index == steps.count - 1 ? denoised : previousSignal * denoised + previousDeviation * noise[i]
        }
        guard result.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        return result
    }
}

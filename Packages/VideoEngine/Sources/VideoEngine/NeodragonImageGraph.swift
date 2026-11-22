import CoreML
import Foundation

/// Executes the separately verified SSD-1B partition plans. Activations stay in
/// Core ML storage; saving a skip connection retains its value without copying.
struct NeodragonImageGraph {
    let runner: ModelRunner

    private struct Plan: Decodable {
        struct Step: Decodable {
            let operation: String
            let model: String?
            let inputs: [String]?
            let output: String?
            let shape: [Int]?
            let source: String?
            let target: String?
            let slot: String?
            let axis: Int?
        }
        let component: String
        let latentShape: [Int]
        let steps: [Step]
    }

    func run(component: String, inputs: [String: MLFeatureValue]) async throws -> MLShapedArray<Float32> {
        let prefix: String, output: String, outputShape: [Int]
        switch component {
        case "ssd_1b_unet":
            prefix = "ssd_unet_"; output = "predicted_noise"; outputShape = [1, 4, 80, 128]
        case "ssd_1b_vae":
            prefix = "ssd_vae_"; output = "decoded_image"; outputShape = [1, 3, 640, 1024]
        default: throw GenerationError.invalidTensor
        }
        let url = runner.directory.appendingPathComponent(component + "_pipeline.json")
        let data = try Data(contentsOf: url)
        guard data.count <= 500_000 else { throw GenerationError.invalidTensor }
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        guard plan.component == component, plan.latentShape == [1, 4, 80, 128],
              (1...300).contains(plan.steps.count) else { throw GenerationError.invalidTensor }
        var values = inputs
        for step in plan.steps {
            try await runner.checkpoint()
            switch step.operation {
            case "predict":
                guard let model = step.model, model.hasPrefix(prefix),
                      model.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      let names = step.inputs, !names.isEmpty, Set(names).count == names.count,
                      let destination = step.output, let shape = step.shape else { throw GenerationError.invalidTensor }
                var features: [String: MLFeatureValue] = [:]
                for name in names {
                    guard let value = values[name] else { throw GenerationError.invalidTensor }
                    features[name] = value
                }
                let result = try await runner.predict(model, features)
                guard let value = result["output"], let array = value.multiArrayValue else { throw GenerationError.invalidTensor }
                try Self.validate(array, shape: shape)
                values[destination] = value
            case "save":
                guard let source = step.source, let target = step.target, let value = values[source],
                      values[target] == nil else { throw GenerationError.invalidTensor }
                values[target] = value
            case "release":
                guard let slot = step.slot, values.removeValue(forKey: slot) != nil else { throw GenerationError.invalidTensor }
            case "concatenate":
                guard let names = step.inputs, names.count == 2, let destination = step.output,
                      step.axis == 1 else { throw GenerationError.invalidTensor }
                let arrays = try names.map { name -> MLMultiArray in
                    guard let value = values[name]?.multiArrayValue, value.dataType == .float32 else { throw GenerationError.invalidTensor }
                    return value
                }
                let a = arrays[0].shape.map(\.intValue), b = arrays[1].shape.map(\.intValue)
                guard a.count == 4, b.count == 4, a[0] == b[0], a[2] == b[2], a[3] == b[3] else {
                    throw GenerationError.invalidTensor
                }
                values[destination] = MLFeatureValue(multiArray: MLMultiArray(concatenating: arrays, axis: 1, dataType: .float32))
            default: throw GenerationError.invalidTensor
            }
        }
        guard let array = values[output]?.multiArrayValue else { throw GenerationError.invalidTensor }
        try Self.validate(array, shape: outputShape)
        return MLShapedArray<Float32>(converting: array)
    }

    /// Checks logical elements, excluding possible storage padding, without
    /// allocating another copy of the large first-image decoder activations.
    static func validate(_ array: MLMultiArray, shape: [Int]) throws {
        let elements = try checkedElementCount(shape)
        guard array.count == elements, array.dataType == .float32,
              array.shape.map(\.intValue) == shape else { throw GenerationError.invalidTensor }
        try array.withUnsafeBufferPointer(ofType: Float32.self) { buffer in
            let strides = array.strides.map(\.intValue)
            guard strides.count == shape.count, strides.allSatisfy({ $0 > 0 }) else { throw GenerationError.invalidTensor }
            var largest = 0
            for (dimension, stride) in zip(shape, strides) {
                let (offset, multiplicationOverflow) = (dimension - 1).multipliedReportingOverflow(by: stride)
                let (sum, additionOverflow) = largest.addingReportingOverflow(offset)
                guard !multiplicationOverflow, !additionOverflow else { throw GenerationError.invalidTensor }
                largest = sum
            }
            guard largest < buffer.count else { throw GenerationError.invalidTensor }
            var expected = 1, contiguous = true
            for dimension in shape.indices.reversed() {
                if shape[dimension] > 1 && strides[dimension] != expected { contiguous = false }
                expected *= shape[dimension]
            }
            if contiguous {
                guard buffer.prefix(elements).allSatisfy({ $0.isFinite }) else { throw GenerationError.invalidTensor }
            } else {
                for linear in 0..<array.count {
                    var remaining = linear, offset = 0
                    for dimension in shape.indices.reversed() {
                        offset += (remaining % shape[dimension]) * strides[dimension]
                        remaining /= shape[dimension]
                    }
                    guard buffer[offset].isFinite else { throw GenerationError.invalidTensor }
                }
            }
        }
    }

    static func checkedElementCount(_ shape: [Int]) throws -> Int {
        // The original SSD-1B VAE's final upsampler emits [1,256,640,1024].
        // Keep the bound at that verified graph size, and reject overflow before
        // multiplication rather than rejecting a legitimate model activation.
        let maximum = 256 * 640 * 1024
        guard (1...5).contains(shape.count), shape.allSatisfy({ (1...16_384).contains($0) }) else {
            throw GenerationError.invalidTensor
        }
        var count = 1
        for dimension in shape {
            guard count <= maximum / dimension else { throw GenerationError.invalidTensor }
            count *= dimension
        }
        return count
    }
}

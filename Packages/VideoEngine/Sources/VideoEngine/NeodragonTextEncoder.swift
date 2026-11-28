import CoreML
import Foundation

struct NeodragonTextEncoding {
    let context: MLShapedArray<Float32>
    let pooled: MLShapedArray<Float32>
    let tokenCount: Int
}

/// Uses the optional package's own four CLIP encoders and distilled T5. Neither
/// pretrained text weights nor tokenizers are substituted with other model components.
struct NeodragonTextEncoder {
    let runner: ModelRunner

    struct CLIPResult {
        let penultimate: MLShapedArray<Float32>
        let pooled: MLShapedArray<Float32>
    }

    func video(_ prompt: String) async throws -> NeodragonTextEncoding {
        let first = try await clip(prompt, component: "text_encoder", tokenizerName: "tokenizer")
        let second = try await clip(prompt, component: "text_encoder_2", tokenizerName: "tokenizer_2")
        let tokens = try t5Tokens(prompt)
        let ids = intFeature(tokens.ids, shape: [1, 128])
        let mask = intFeature((0..<128).map { $0 < tokens.count ? 1 : 0 }, shape: [1, 128])
        let text = try await runner.predict("text_encoder_3", ["input_ids": ids, "attention_mask": mask])
        let hidden = try tensor(text, "output")
        try validate(hidden, shape: [1, 128, 4096], label: "text_encoder_3")
        let adapted = try await runner.predict("context_adapter", ["prompt_embeddings": feature(hidden)])
        let context = try tensor(adapted, "output")
        try validate(context, shape: [1, 128, 1536], label: "context_adapter")
        let pooled = MLShapedArray(concatenating: [first.pooled, second.pooled], alongAxis: 1)
        try validate(pooled, shape: [1, 2048], label: "video_pooled")
        return .init(context: context, pooled: pooled, tokenCount: tokens.count)
    }

    func firstFrame(_ prompt: String) async throws -> (hidden: MLShapedArray<Float32>, pooled: MLShapedArray<Float32>) {
        let first = try await clip(prompt, component: "ssd_1b_text_encoder", tokenizerName: "ssd_1b_tokenizer")
        let second = try await clip(prompt, component: "ssd_1b_text_encoder_2", tokenizerName: "ssd_1b_tokenizer_2")
        let hidden = MLShapedArray(concatenating: [first.penultimate, second.penultimate], alongAxis: 2)
        try validate(hidden, shape: [1, 77, 2048], label: "first_image_context")
        try validate(second.pooled, shape: [1, 1280], label: "first_image_pooled")
        return (hidden, second.pooled)
    }

    func clip(_ prompt: String, component: String, tokenizerName: String) async throws -> CLIPResult {
        let pairs = ["text_encoder": "tokenizer", "text_encoder_2": "tokenizer_2",
                     "ssd_1b_text_encoder": "ssd_1b_tokenizer", "ssd_1b_text_encoder_2": "ssd_1b_tokenizer_2"]
        guard pairs[component] == tokenizerName else { throw GenerationError.invalidTensor }
        struct Plan: Decodable {
            struct Part: Decodable { let name: String; let inputs: [String]; let output: String }
            let component: String
            let hiddenSize: Int
            let projectionSize: Int
            let penultimatePartition: String
            let partitions: [Part]
        }
        let data = try Data(contentsOf: runner.directory.appendingPathComponent(component + "_pipeline.json"))
        guard data.count < 100_000 else { throw GenerationError.invalidTensor }
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        guard plan.component == component, [768, 1280].contains(plan.hiddenSize),
              [768, 1280].contains(plan.projectionSize), (6...11).contains(plan.partitions.count),
              plan.partitions.first?.name == component + "_embedding", plan.partitions.last?.name == component + "_pool",
              plan.partitions.contains(where: { $0.name == plan.penultimatePartition }) else { throw GenerationError.invalidTensor }
        let tokenizer = try NeodragonCLIPTokenizer(directory: runner.directory.appendingPathComponent(tokenizerName))
        let ids = intFeature(try tokenizer.encode(prompt), shape: [1, 77])
        var hidden: MLFeatureValue?
        var penultimate: MLShapedArray<Float32>?
        for part in plan.partitions {
            guard part.name.hasPrefix(component + "_"), !part.name.contains("/"), !part.name.contains(".."),
                  ["hidden", "hidden_out", "pooled"].contains(part.output) else { throw GenerationError.invalidTensor }
            var inputs: [String: MLFeatureValue] = [:]
            for name in part.inputs {
                if name == "input_ids" { inputs[name] = ids }
                else if name == "hidden", let hidden { inputs[name] = hidden }
                else { throw GenerationError.invalidTensor }
            }
            let result = try await runner.predict(part.name, inputs)
            let array = try tensor(result, part.output)
            try validate(array, shape: part.output == "pooled" ? [1, plan.projectionSize] : [1, 77, plan.hiddenSize], label: part.name,
                         source: result[part.output]?.multiArrayValue)
            hidden = feature(array)
            if part.name == plan.penultimatePartition { penultimate = array }
        }
        guard let hidden, let penultimate, let multiArray = hidden.multiArrayValue else { throw GenerationError.invalidTensor }
        return .init(penultimate: penultimate, pooled: MLShapedArray<Float32>(converting: multiArray))
    }

    func t5Tokens(_ prompt: String) throws -> (ids: [Int32], count: Int) {
        try NeodragonT5Tokenizer(directory: runner.directory.appendingPathComponent("tokenizer_3")).encode(prompt)
    }

    private func validate(_ array: MLShapedArray<Float32>, shape: [Int], label: String, source: MLMultiArray? = nil) throws {
        let nonFinite = array.scalars.reduce(0) { $0 + ($1.isFinite ? 0 : 1) }
        guard array.shape == shape, nonFinite == 0 else {
            var fields = ["shape": String(describing: array.shape), "expectedShape": String(describing: shape), "nonFiniteValues": String(nonFinite)]
            if let source {
                fields["rawDataType"] = String(source.dataType.rawValue)
                fields["rawStrides"] = String(describing: source.strides.map(\.intValue))
                // Error-path diagnostic independent of MLShapedArray conversion.
                // Read only logical elements through Core ML's indexed API.
                var rawNaN = 0, rawInfinite = 0
                let dimensions = source.shape.map(\.intValue)
                for linear in 0..<source.count {
                    var remainder = linear, coordinates = Array(repeating: 0, count: dimensions.count)
                    for dimension in dimensions.indices.reversed() {
                        coordinates[dimension] = remainder % dimensions[dimension]
                        remainder /= dimensions[dimension]
                    }
                    let number = source[coordinates.map(NSNumber.init(value:))].doubleValue
                    if number.isNaN { rawNaN += 1 }
                    else if !number.isFinite { rawInfinite += 1 }
                }
                fields["rawLogicalNaN"] = String(rawNaN)
                fields["rawLogicalInfinite"] = String(rawInfinite)
            }
            let detail = "Neodragon \(label): shape \(array.shape), expected \(shape), non-finite values \(nonFinite); raw \(fields["rawLogicalNaN"] ?? "unknown") NaN, \(fields["rawLogicalInfinite"] ?? "unknown") infinite"
            runner.benchmark?.record("tensor_validation_failed", partition: label, phase: "output-validation",
                                     fields: fields)
            throw GenerationError.incompatibleModel(detail)
        }
    }

    private func intFeature(_ values: [Int32], shape: [Int]) -> MLFeatureValue {
        MLFeatureValue(multiArray: MLMultiArray(MLShapedArray<Int32>(scalars: values, shape: shape)))
    }
}

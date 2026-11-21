import CoreML
import Foundation

/// Planner predictions only. This does not measure actual hardware execution or utilization.
public actor ComputePlanAudit {
    public init() {}

    public func run(modelsAt directory: URL, log: BenchmarkLog,
                    progress: @Sendable (GenerationProgress) -> Void) async throws {
        try MOVDModel.validateInstallation(at: directory)
        let configurations: [(String, MLComputeUnits)] = [
            ("cpuOnly", .cpuOnly), ("cpuAndGPU", .cpuAndGPU),
            ("cpuAndNeuralEngine", .cpuAndNeuralEngine), ("all", .all)
        ]
        for (index, name) in MOVDModel.requiredNames.enumerated() {
            for (label, units) in configurations {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical else {
                    throw GenerationError.tooHot
                }
                progress(.init(Double(index) / Double(MOVDModel.requiredNames.count), "Inspecting \(name) · \(label)"))
                let start = log.begin(name, phase: "compute_plan", fields: ["requestedComputeUnits": label])
                do {
                    let configuration = MLModelConfiguration()
                    configuration.computeUnits = units
                    let plan = try await MLComputePlan.load(contentsOf: directory.appendingPathComponent(name + ".mlmodelc"), configuration: configuration)
                    log.end(name, phase: "compute_plan", started: start, fields: ["requestedComputeUnits": label])
                    inspect(plan.modelStructure, plan: plan, name: name, configuration: label, log: log)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    log.end(name, phase: "compute_plan", started: start, error: error, fields: ["requestedComputeUnits": label])
                    // Unsupported plans are evidence; continue inspecting other configurations.
                }
            }
        }
        progress(.init(1, "Compute-plan inspection finished"))
    }

    private func inspect(_ structure: MLModelStructure, plan: MLComputePlan, name: String, configuration: String, log: BenchmarkLog) {
        switch structure {
        case .program(let program):
            for key in program.functions.keys.sorted() {
                if let function = program.functions[key] { inspect(function.block, plan: plan, name: name, configuration: configuration, log: log) }
            }
        case .neuralNetwork(let network):
            for layer in network.layers {
                emit(layer.type, outputs: layer.outputNames, usage: plan.deviceUsage(for: layer), cost: nil, name: name, configuration: configuration, log: log)
            }
        case .pipeline(let pipeline):
            for model in pipeline.subModels { inspect(model, plan: plan, name: name, configuration: configuration, log: log) }
        case .unsupported:
            log.record("compute_plan_unsupported", partition: name, fields: ["requestedComputeUnits": configuration])
        @unknown default:
            log.record("compute_plan_unknown_structure", partition: name, fields: ["requestedComputeUnits": configuration])
        }
    }

    private func inspect(_ block: MLModelStructure.Program.Block, plan: MLComputePlan, name: String, configuration: String, log: BenchmarkLog) {
        for operation in block.operations {
            emit(operation.operatorName, outputs: operation.outputs.map(\.name), usage: plan.deviceUsage(for: operation),
                 cost: plan.estimatedCost(of: operation)?.weight, name: name, configuration: configuration, log: log)
            for child in operation.blocks { inspect(child, plan: plan, name: name, configuration: configuration, log: log) }
        }
    }

    private func emit(_ operation: String, outputs: [String], usage: MLComputePlan.DeviceUsage?, cost: Double?,
                      name: String, configuration: String, log: BenchmarkLog) {
        var fields = ["operation": operation, "outputs": outputs.joined(separator: ","), "requestedComputeUnits": configuration,
                      "evidenceType": "planner estimate, not observed execution"]
        if let usage {
            fields["preferredDevice"] = deviceLabel(usage.preferred)
            fields["supportedDevices"] = usage.supported.map(deviceLabel).joined(separator: ",")
        } else { fields["preferredDevice"] = "unavailable" }
        if let cost { fields["estimatedRelativeCost"] = String(cost) }
        log.record("compute_plan_operation", partition: name, fields: fields)
    }

    private func deviceLabel(_ device: MLComputeDevice) -> String {
        switch device {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .neuralEngine: return "NeuralEngine"
        @unknown default: return "unknown"
        }
    }
}

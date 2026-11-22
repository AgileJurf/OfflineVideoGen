import Foundation

// Standalone verification uses the production scheduler and the independently
// generated diffusers fixture. No model or service is needed for this check.
enum GenerationError: Error { case invalidTensor }

@main
struct CheckLCM {
    struct Fixture: Decodable {
        struct Step: Decodable { let timestep: Float32; let noise: [Float32]; let reference: [Float32] }
        let sample: [Float32]; let prediction: [Float32]; let steps: [Step]
    }
    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let scheduler = NeodragonImageScheduler()
        precondition(fixture.steps.count == scheduler.steps.count)
        for (index, step) in fixture.steps.enumerated() {
            precondition(step.timestep == scheduler.steps[index].timestep)
            let actual = try scheduler.advance(index: index, sample: fixture.sample, prediction: fixture.prediction, noise: step.noise)
            precondition(zip(actual, step.reference).allSatisfy { abs($0 - $1) <= 1e-6 })
        }
        print("Passed all four original SSD-1B LCM reference steps")
    }
}

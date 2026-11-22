import CryptoKit
import Foundation

@main
struct CheckPyramid {
    struct Fixture: Decodable {
        struct Case: Decodable {
            struct Rotation: Decodable { let token: Int; let cosine: [Float32]; let sine: [Float32] }
            let lengths: [Int]; let textTokenCount: Int; let maskSHA256: String; let rotary: [Rotation]
        }
        struct Grid: Decodable { let height: Int; let width: Int; let values: [Float32]; let downsample: [Float32]; let upsample: [Float32] }
        let cases: [Case]; let grid: Grid
    }
    static func equal(_ actual: [Float32], _ expected: [Float32], tolerance: Float32 = 1e-6) {
        precondition(actual.count == expected.count)
        precondition(zip(actual, expected).allSatisfy { $0.isFinite && abs($0 - $1) <= tolerance })
    }
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        for item in fixture.cases {
            let layout = NeodragonAttentionLayout(lengths: item.lengths, textTokenCount: item.textTokenCount)
            let digest = layout.mask.withUnsafeBytes { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
            precondition(digest == item.maskSHA256, "Causal mask differs from original model")
            for rotation in item.rotary {
                let range = (rotation.token * 32)..<((rotation.token + 1) * 32)
                equal(Array(layout.cosine[range]), rotation.cosine)
                equal(Array(layout.sine[range]), rotation.sine)
            }
        }
        let grid = NeodragonGrid(values: fixture.grid.values, height: fixture.grid.height, width: fixture.grid.width)
        equal(grid.downsample().values, fixture.grid.downsample)
        equal(grid.downsample(variancePreserving: true).values, fixture.grid.downsample.map { $0 * 2 })
        equal(grid.nearestUpsample().values, fixture.grid.upsample)
        var first = NeodragonRandom(seed: 42), second = NeodragonRandom(seed: 42)
        let values = first.normals(count: 100_000)
        equal(values, second.normals(count: values.count), tolerance: 0)
        let mean = values.map(Double.init).reduce(0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
        precondition(abs(mean) < 0.015 && abs(variance - 1) < 0.015)
        print("Passed original-model causal masks, rotary positions through nine seconds, spatial operators and deterministic native noise checks")
    }
}

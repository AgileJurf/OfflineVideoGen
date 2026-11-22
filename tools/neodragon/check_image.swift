import CryptoKit
import Foundation

enum GenerationError: Error { case invalidTensor }

@main
struct CheckImage {
    struct Fixture: Decodable {
        struct Case: Decodable { let kind: String; let outputSHA256: String }
        let width: Int; let height: Int; let cases: [Case]; let decoded: [Float32]; let pixels: [UInt8]
    }
    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let rounded = try NeodragonImageProcessing.imageBytes(fixture.decoded)
        precondition(rounded == fixture.pixels)
        for item in fixture.cases {
            var input = [UInt8](); input.reserveCapacity(3 * fixture.width * fixture.height)
            for channel in 0..<3 {
                for y in 0..<fixture.height {
                    for x in 0..<fixture.width {
                        let value: Int
                        switch item.kind {
                        case "pattern": value = (x * 17 + y * 31 + channel * 73 + (x ^ y) * 13) % 256
                        case "gradient": value = (channel == 0 ? x : channel == 1 ? y : x + y) % 256
                        case "checker": value = (x + y) % 2 * 255
                        case "black": value = 0
                        case "white": value = 255
                        default: fatalError("Unknown fixture")
                        }
                        input.append(UInt8(value))
                    }
                }
            }
            let output = try NeodragonImageProcessing.downsampleRGB(input, width: fixture.width, height: fixture.height)
            let hash = SHA256.hash(data: Data(output)).map { String(format: "%02x", $0) }.joined()
            precondition(hash == item.outputSHA256, "Pillow Lanczos mismatch: \(item.kind)")
        }
        print("Passed first-image byte rounding and five full-resolution Pillow Lanczos cases exactly")
    }
}

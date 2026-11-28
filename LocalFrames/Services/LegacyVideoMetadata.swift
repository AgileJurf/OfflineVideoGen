import Foundation

// Read-only metadata compatibility for existing library items.
struct SmoothingProvenance: Codable, Hashable {
    let provider: String
    let method: String
    let sourceSHA256: String
    let sourceFrames: Int
    let returnedFrames: Int
    let terminalHoldFrames: Int
    let elapsedSeconds: Double
}


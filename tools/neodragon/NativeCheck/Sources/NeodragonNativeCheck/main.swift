import AVFoundation
import CoreML
import Foundation
import VideoEngine

@main
struct NativeGenerationCheck {
    struct Index: Decodable {
        struct Model: Decodable { let name: String; let packagePath: String; let fingerprint: String }
        let maximumSeconds: Int; let models: [Model]
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 3, let seconds = Int(CommandLine.arguments[2]) else {
            fatalError("Usage: NeodragonNativeCheck runtime-fixture seconds")
        }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture.appendingPathComponent("package-index.json")))
        guard (2...index.maximumSeconds).contains(seconds) else { fatalError("Duration exceeds this package's range") }
        let fm = FileManager.default
        let compiled = fixture.appendingPathComponent("Compiled-macos-cpu", isDirectory: true)
        try fm.createDirectory(at: compiled, withIntermediateDirectories: true)
        for (position, item) in index.models.enumerated() {
            let destination = compiled.appendingPathComponent(item.name + ".mlmodelc")
            let stamp = compiled.appendingPathComponent(item.name + ".compile-stamp")
            let expected = item.fingerprint + "\nmacos\n" + ProcessInfo.processInfo.operatingSystemVersionString
            if fm.fileExists(atPath: destination.path), (try? String(contentsOf: stamp, encoding: .utf8)) == expected { continue }
            print("NEODRAGON_MAC_COMPILE \(position + 1)/\(index.models.count) \(item.name)")
            let result = try await MLModel.compileModel(at: URL(fileURLWithPath: item.packagePath))
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: result, to: destination)
            try expected.write(to: stamp, atomically: true, encoding: .utf8)
        }
        for source in try fm.contentsOfDirectory(at: fixture.appendingPathComponent("support"), includingPropertiesForKeys: nil) {
            let destination = compiled.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        }
        let installed = try NeodragonEngine.validateInstallation(at: compiled)
        let run = fixture.appendingPathComponent("generation-\(seconds)s-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: run, withIntermediateDirectories: true)
        let output = run.appendingPathComponent("sailboat-seed42.mp4")
        let geometry = try NeodragonModel.geometry(seconds: seconds)
        let log = try BenchmarkLog(url: run.appendingPathComponent("generation.jsonl"), kind: "generation", metadata: [
            "modelID": NeodragonModel.identifier, "modelRevision": NeodragonModel.weightsRevision,
            "expectedPartitions": installed.modelNames.joined(separator: ","),
            "expectedEvaluations": String(4 + (geometry.latentFrames - 1) * 3),
            "durationSeconds": String(seconds), "width": "512", "height": "320", "fps": "24", "seed": "42",
            "scope": "Native macOS CPU full-pipeline functional check; not an iPhone benchmark"])
        print("NEODRAGON_MAC_OUTPUT \(run.path)")
        do {
            let request = try NeodragonGenerationRequest(prompt: "A small sailboat glides across a calm lake at sunrise.", duration: seconds, seed: 42)
            let metrics = try await NeodragonEngine().generate(request, modelsAt: compiled, output: output, benchmark: log, computeOnCPUOnly: true) {
                print("NEODRAGON_MAC_PROGRESS \($0.fraction) \($0.message)")
            }
            try JSONEncoder().encode(metrics).write(to: run.appendingPathComponent("metrics.json"))
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw GenerationError.invalidTensor }
            let size = try await track.load(.naturalSize)
            let fps = try await track.load(.nominalFrameRate)
            let reader = try AVAssetReader(asset: asset)
            let samples = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(samples)
            guard reader.startReading() else { throw GenerationError.invalidTensor }
            var frames = 0
            while samples.copyNextSampleBuffer() != nil { frames += 1 }
            guard reader.status == .completed, frames == seconds * 24,
                  size == CGSize(width: 512, height: 320), abs(fps - 24) < 0.01,
                  abs(duration.seconds - Double(seconds)) < 1.0 / 24.0 else { throw GenerationError.invalidTensor }
            try log.finish(status: "completed", fields: ["exportedFrames": String(frames)])
            print("NEODRAGON_MAC_COMPLETED \(seconds)s \(frames) frames; physical iPhone acceptance still required")
        } catch {
            try? log.finish(status: "failed", fields: ["error": String(describing: error)])
            throw error
        }
    }
}

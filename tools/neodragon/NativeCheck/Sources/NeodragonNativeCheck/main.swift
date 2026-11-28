import AVFoundation
import CoreML
import CryptoKit
import Foundation
import VideoEngine

@main
struct NativeGenerationCheck {
    struct Index: Decodable {
        struct Model: Decodable { let name: String; let packagePath: String; let fingerprint: String }
        let maximumSeconds: Int; let models: [Model]
    }

    static func main() async throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--verify-existing",
           let seconds = Int(CommandLine.arguments[3]) {
            let output = URL(fileURLWithPath: CommandLine.arguments[2])
            let result = try await verifyExport(output, seconds: seconds)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.deletingLastPathComponent().appendingPathComponent("export-revalidation.json"), options: .withoutOverwriting)
            print(String(decoding: data, as: UTF8.self))
            return
        }
        guard CommandLine.arguments.count >= 3, let seconds = Int(CommandLine.arguments[2]) else {
            fatalError("Usage: NeodragonNativeCheck runtime-fixture seconds [--attention-runtime path] [--prompt text] [--upstream-detail] OR --verify-existing video.mp4 seconds")
        }
        var attentionFixture: URL?
        var prompt = "A small sailboat glides across a calm lake at sunrise."
        var upstreamDetail = false
        var compileOnly = false
        var position = 3
        while position < CommandLine.arguments.count {
            let argument = CommandLine.arguments[position]
            if argument == "--upstream-detail" { upstreamDetail = true; position += 1; continue }
            if argument == "--compile-only" { compileOnly = true; position += 1; continue }
            guard position + 1 < CommandLine.arguments.count else { fatalError("Missing option value") }
            switch argument {
            case "--attention-runtime": attentionFixture = URL(fileURLWithPath: CommandLine.arguments[position + 1], isDirectory: true)
            case "--prompt": prompt = CommandLine.arguments[position + 1]
            default: fatalError("Unknown option")
            }
            position += 2
        }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture.appendingPathComponent("package-index.json")))
        guard (2...index.maximumSeconds).contains(seconds) else { fatalError("Duration exceeds this package's range") }
        let fm = FileManager.default
        let compiled = try await compile(fixture)
        var attentionCompiled: URL?
        if let attentionFixture {
            attentionCompiled = try await compile(attentionFixture)
            _ = try NeodragonAttentionVariant.validateInstallation(at: attentionCompiled!)
        }
        let installed = try NeodragonEngine.validateInstallation(at: compiled)
        if compileOnly { print("NEODRAGON_MAC_COMPILE_VALIDATED \(installed.modelNames.count) base components"); return }
        let run = (attentionFixture ?? fixture).appendingPathComponent("generation-\(seconds)s-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: run, withIntermediateDirectories: true)
        let output = run.appendingPathComponent("sailboat-seed42.mp4")
        let geometry = try NeodragonModel.geometry(seconds: seconds)
        let log = try BenchmarkLog(url: run.appendingPathComponent("generation.jsonl"), kind: "generation", metadata: [
            "modelID": NeodragonModel.identifier, "modelRevision": NeodragonModel.weightsRevision,
            "expectedPartitions": installed.modelNames.joined(separator: ","),
            "expectedEvaluations": String(4 + (geometry.latentFrames - 1) * 3),
            "durationSeconds": String(seconds), "width": "512", "height": "320", "fps": "24", "seed": "42",
            "prompt": prompt, "upstreamDetail": String(upstreamDetail),
            "profileID": attentionFixture == nil ? NeodragonMotionComputePolicy.cpuCompatibility.profileID : NeodragonAttentionVariant.profileID,
            "scope": "Native macOS CPU full-pipeline functional check; not an iPhone benchmark"])
        print("NEODRAGON_MAC_OUTPUT \(run.path)")
        do {
            let request = try NeodragonGenerationRequest(prompt: prompt, duration: seconds, seed: 42,
                modelPrompt: upstreamDetail ? NeodragonPromptConditioning.upstreamDetail(prompt) : nil)
            let metrics = try await NeodragonEngine().generate(request, modelsAt: compiled, output: output, benchmark: log, computeOnCPUOnly: true,
                motionComputePolicy: .cpuCompatibility, attentionVariantAt: attentionCompiled) {
                print("NEODRAGON_MAC_PROGRESS \($0.fraction) \($0.message)")
            }
            try JSONEncoder().encode(metrics).write(to: run.appendingPathComponent("metrics.json"))
            let validation = try await verifyExport(output, seconds: seconds)
            try JSONSerialization.data(withJSONObject: validation, options: [.prettyPrinted, .sortedKeys]).write(to: run.appendingPathComponent("export-validation.json"))
            let frames = validation["decodedFrames"] as! Int
            try log.finish(status: "completed", fields: ["exportedFrames": String(frames)])
            print("NEODRAGON_MAC_COMPLETED \(seconds)s \(frames) frames; physical iPhone acceptance still required")
        } catch {
            try? log.finish(status: "failed", fields: ["error": String(describing: error)])
            throw error
        }
    }

    static func compile(_ fixture: URL) async throws -> URL {
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture.appendingPathComponent("package-index.json")))
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
        return compiled
    }

    static func verifyExport(_ output: URL, seconds: Int) async throws -> [String: Any] {
        guard (2...9).contains(seconds) else { throw GenerationError.invalidTensor }
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw GenerationError.invalidTensor }
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let reader = try AVAssetReader(asset: asset)
        // Compressed reads can include zero-sample marker buffers. Count real
        // decoded image buffers instead of treating each compressed buffer as a frame.
        let samples = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(samples)
        guard reader.startReading() else { throw GenerationError.invalidTensor }
        var frames = 0
        while let sample = samples.copyNextSampleBuffer() {
            guard CMSampleBufferGetImageBuffer(sample) != nil else { throw GenerationError.invalidTensor }
            frames += 1
        }
        guard reader.status == .completed, frames == seconds * 24,
              size == CGSize(width: 512, height: 320), abs(fps - 24) < 0.01,
              abs(duration.seconds - Double(seconds)) < 1.0 / 24.0 else { throw GenerationError.invalidTensor }
        let data = try Data(contentsOf: output)
        return ["status": "passed-decoded-export-check", "decodedFrames": frames,
                "width": Int(size.width), "height": Int(size.height), "fps": fps,
                "durationSeconds": duration.seconds,
                "videoSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
    }
}

# Local Frames

A standalone SwiftUI research application for offline text-to-video generation on iPhone, using the released MOVD / Open-Sora Core ML model partitions.

**Development status: experimental. Xcode Cloud Build 2 passed its simulator test and iOS analysis actions. No successful full-model inference has been demonstrated yet.** Build and simulator test results do not establish iPhone memory, thermal, Neural Engine, or generation performance.

The initial target is 256 × 256, 12 FPS, and 2–5 seconds. Inference uses temporal video diffusion and a video VAE. Model files download once and remain in the app sandbox; generation has no network service dependency.

This repository is independent of other applications. It contains no model weights, developer credentials, or device identifiers.

## Build and test

Open `LocalFrames.xcodeproj` in Xcode 16.4 or newer and select the shared **LocalFrames** scheme. The app requires iOS 18 or newer. Swift package versions are locked in `Package.resolved`.

```sh
xcodebuild -project LocalFrames.xcodeproj -scheme LocalFrames \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

Use **Product → Test** with an available iPhone simulator to run the unit and UI suites. They check prompt validation, model gating, checksums, MP4 encoding, library persistence, and navigation. Synthetic pixels are used only as an encoder test fixture; those tests do not run diffusion or establish generation quality.

For device builds, choose your Apple Developer team under Signing & Capabilities for all three targets. See [Xcode Cloud setup](docs/XCODE_CLOUD.md) for the cloud-first test workflow.

## Model installation and generation

In **Setup**, install the MOVD model over Wi-Fi. The three upstream archives total **14,133,836,614 bytes**. The app requires 50 GB free during extraction and compilation; that is a conservative setup allowance, not a measured installed size. SHA-256 checks occur before extraction. Downloads can resume when the server supplies valid resume data; interrupted model compilation starts again.

After installation, enter a short prompt, select 2–5 seconds, and generate with the app in the foreground. The engine performs T5 prompt encoding, STDiT temporal diffusion, temporal/spatial VAE decoding, and H.264 MP4 encoding locally. It loads one Core ML partition at a time. Cancellation and thermal/memory checks occur between predictions; a running Core ML prediction cannot be interrupted immediately.

The library supports playback, replay, deletion, regeneration, Photos saving, and Files export. A completed generation stores its seed and sampled timing/memory/thermal metrics locally. No analytics or remote inference service is configured.

## Evidence and remaining work

- [Feasibility and model choice](docs/FEASIBILITY.md)
- [Validation record and acceptance gates](docs/VALIDATION.md)
- [Third-party code and model provenance](docs/THIRD_PARTY_NOTICES.md)

The released weights have been downloaded and hashed locally, and all 103 package specifications were inspected. The app and both test targets compile with Xcode 16.4; seven unit and two UI tests passed on the iOS 18.4 simulator with ad hoc signing. Full-model inference, prompt quality, offline completion, peak memory, repeated generation, Photos export, and physical iPhone behavior remain unverified. Do not describe this build as a proven offline video generator until those gates pass.

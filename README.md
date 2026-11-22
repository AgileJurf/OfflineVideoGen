# Local Frames

A standalone SwiftUI research application for offline text-to-video generation on iPhone, using the released MOVD / Open-Sora Core ML model partitions.

**Development status: experimental, with incremental device validation required.** See the [validation record](docs/VALIDATION.md) for software checks and [generation compatibility report](docs/GENERATION_EXPANSION.md) for enabled and blocked features. Build and simulator tests do not establish iPhone performance or video quality. New device journals and output evidence remain private.

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

The [internal TestFlight guide](docs/TESTFLIGHT.md) covers installation, model setup, and the first offline test on an iPhone.

## Model installation and generation

In **Setup**, install the MOVD model over Wi-Fi. The three upstream archives total **14,133,836,614 bytes**. The app requires 50 GB free during extraction and compilation; that is a conservative setup allowance, not a measured installed size. SHA-256 checks occur before extraction. Downloads can resume when the server supplies valid resume data; interrupted model compilation starts again.

After installation, enter a short prompt, select 2–5 seconds, and start generation. The engine performs T5 prompt encoding, STDiT temporal diffusion, temporal/spatial VAE decoding, and H.264 MP4 encoding locally. It loads one Core ML partition at a time. Serious/critical heat pauses work until nominal; cancellation and memory checks remain active. A running Core ML prediction cannot be interrupted immediately.

The 2-second benchmark saves completed motion steps and offers **Resume saved baseline** after relaunch. iOS 26+ builds request supported background GPU execution; if unavailable, work pauses while the app is backgrounded and continues on returning. Background time is controlled by iOS. See [continuation and recovery](docs/RESUMABLE_BASELINE.md) for measured versus unverified behavior.

The library supports playback, replay, deletion, regeneration, Photos saving, and Files export. A completed generation stores its seed and sampled timing/memory/thermal metrics locally. No analytics or remote inference service is configured.

Create offers twelve prompt-based visual styles with an explicit 63-token scene-plus-style budget, fixed seeds, and saved settings. Default preserves the unstyled prompt. Portrait and landscape options create clearly labeled 144 × 256 / 256 × 144 center-cropped copies; the native square original is retained. Image-to-video and AI continuation remain unavailable pending compatible encoder and conditioning exports. The capability screen explains these limits. No additional model is downloaded by these controls.

Optional local diagnostics for Create jobs can be enabled in Setup. They include prompts and remain on the device unless manually exported. The benchmark screen supports side-by-side playback; precision and faster sampler presets require measured physical-device comparisons before activation.

## Optional online support

Build 25 adds **Setup → Online support and model updates → Enable online support**. It defaults off. When enabled, users can manually check the live model catalog over Wi-Fi and cache the validated result for offline use. Enabling the switch alone makes no request; generation does not depend on the backend. Existing installations do not need to download the model again.

A user can separately review and consent to one structured diagnostic report. Its allowlist excludes prompts, seeds, videos, personal files and raw journals. Reports use private storage with a 30-day expiration and limited free intake capacity. Turning support off cancels support requests; nothing is queued automatically. The [service](https://localframes-support.vercel.app) runs on Vercel Hobby, with [deployment and quota documentation](support/README.md) and a [test/release report](docs/SUPPORT_TEST_REPORT.md).

Build 35 provides optional **24 FPS smoothing (beta)**, offering a separate interpolated copy of an original 2-second, 256 × 256, 12 FPS clip. Under Enable online support, choose a clip, preview the frozen local copy, and approve that specific upload to the community Hugging Face `1inkusFace/RIFE` Space. Each retry requires fresh consent. The connection update adds optional free-account OAuth, pre-upload eligibility/quota checks and the helper’s queue protocol. A live iOS Simulator app test saved and validated a 24 FPS copy; physical-iPhone acceptance remains pending. Anonymous access remains available, and neither path purchases credits or falls back to paid services. Free quota may be unavailable. The original, offline inference and local library remain independent of the helper. This does not accelerate diffusion. See the [integration and test report](docs/ONLINE_SMOOTHING.md) and [research evidence](docs/HYBRID_SUPPORT_RESEARCH.md).

## Evidence and remaining work

- [Feasibility and model choice](docs/FEASIBILITY.md)
- [Validation record and acceptance gates](docs/VALIDATION.md)
- [Device benchmark evidence and procedure](docs/BENCHMARK_REPORT.md)
- [Optimization and reproducible comparison protocol](docs/OPTIMIZATION_PHASE2.md)
- [Synthetic precision screening](docs/PRECISION_SCREENING.md)
- [Generation expansion and exact model blockers](docs/GENERATION_EXPANSION.md)
- [Expansion test report](docs/EXPANSION_TEST_REPORT.md)
- [Third-party code and model provenance](docs/THIRD_PARTY_NOTICES.md)

The released weights have been downloaded and hashed locally, and all 103 package specifications were inspected. Regression tests cover the tokenizer, saved-baseline compatibility, video writing, crop geometry, library metadata and UI persistence. Every new inference configuration still requires fresh physical-device completion, numerical and visual checks, offline testing and repeated measurements. The original model and build-18 rollback source are preserved.

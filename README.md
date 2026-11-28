# LOCAL FRAMES

A standalone native SwiftUI studio for genuine offline video diffusion on iPhone. The active engine is **Qualcomm AI Research Neodragon**, with Core ML conversion and runtime code in this repository. It has no dependency on JurfPod or remote AI inference.

The development branch `feature/snapdragon-studio` combines the Liquid Glass redesign with legacy retirement. It is not merged into production. The working Build 44 checkpoint remains available as `baseline/testflight-build-44`.

## Current capabilities

- Neodragon hybrid checkpoint: SSD-1B first image, Pyramid MMDiT motion diffusion, causal video decoding. Hybrid means local model stages, not cloud assistance.
- Native 512 × 320 (16:10) output at 24 FPS. The package supports 2–9-second tensor shapes. Two-second physical-device completion is established; longer durations remain experimental, with a reported five-second memory-pressure cancellation under investigation.
- Unchanged working weights, mixed FP16/FP32 precision, Float32 T5, four-step image LCM and three motion evaluations per subsequent latent unit. CPU motion compatibility preserves the Build 44 runtime fix.
- 58 local **prompt-based** styles and editable custom conditioning. Original prompts and versioned style settings remain separate from effective model prompts. The complete prompt must fit every actual tokenizer; nothing is silently shortened. No trained style adapter or unvalidated style-strength control is advertised.
- Four native tabs: Create, Library, Models and Settings. Native Liquid Glass on compatible SDKs/OS versions, accessible material/opaque fallbacks on iOS 18, system/light/dark appearance, keyboard dismissal, native AVKit playback and cached thumbnails.
- Frame Lab, measured local journals, bounded running job log, elapsed time and measured motion-stage estimates. Estimates are not full-job guarantees.
- Files app access under **On My iPhone → Local Frames → Videos / Benchmarks**. Export copies are separate from the private library. Settings and Frame Lab prominently expose **Export Benchmark Files**.

Image conditioning, AI continuation, alternative native aspect ratios, AI audio, trained style adapters and new Fast/Balanced/Cinema configurations are not exposed as working capabilities. See [studio migration and validation](docs/STUDIO_MIGRATION.md).

## Install and run

Open `LocalFrames.xcodeproj`, using the existing LocalFrames scheme and application identity. Minimum deployment remains iOS 18. The modern glass code uses compile-time SDK and runtime OS gates; Xcode Cloud is authoritative for those APIs.

In Models, explicitly confirm installation of Neodragon. Eight pinned SHA-256-verified archives total **7,881,071,452 bytes**. Installation requires **32,212,254,720 bytes** free for download, extraction and compilation. Existing installations are reused at the same sandbox path. Downloads resume when the server provides valid resume data. Generation and styles require no network after installation.

This branch has no MOVD inference engine, model selector or download manifest, and no online assistant, Hugging Face sign-in or smoothing uploader. An audited, journaled one-time migration removes exact retired files while preserving the active Neodragon package, videos, metadata and settings. Storage reports actual deleted file bytes, not a promised amount.

## Validation and rollback

Routine unit/UI tests use lightweight fixtures and never download model weights. Real-model tests are explicit opt-in tests and are skipped without their private local assets. Simulator success is not evidence of physical-device inference performance.

The manual Xcode Cloud workflow **LOCAL FRAMES — Liquid Glass Development** uses the existing developer team, bundle identifier and App Store Connect record. It analyzes, tests one simulator destination, archives and distributes only to internal testers. No production merge or public distribution is authorized by this branch.

[Neodragon conversion record](docs/NEODRAGON_IMPLEMENTATION.md) · [upstream source](https://github.com/qualcomm-ai-research/neodragon) · [upstream weights](https://huggingface.co/Qualcomm-AI-Research/Neodragon) · [model tooling and licenses](tools/neodragon/README.md)

Historical documents under `docs/` describe earlier builds and experiments. Their old model/helper setup instructions do not apply to this branch. Private device journals, videos, native crash reports and current test artifacts stay in ignored `build/`; they are not uploaded by CI or the app.

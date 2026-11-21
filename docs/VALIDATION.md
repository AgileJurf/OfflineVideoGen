# Validation record

## Observed results

| Check | Status |
| --- | --- |
| Model archive download and SHA-256 calculation | Completed for all three upstream archives |
| Shared Xcode project and pinned packages | Present |
| Xcode 16.4 generic iOS simulator build-for-testing | Passed for the app, unit tests, and UI tests |
| Local simulator test execution | Passed: 7 unit + 2 UI tests, 0 failures; iPhone 16 Pro Max simulator, iOS 18.4, ad hoc signing |
| Model specification inspection | Parsed all 103 package specifications; corrected the int32-to-float32 temporal-count boundary |
| Xcode Cloud workflow | Build 2 passed both required actions: Test — iOS and Analyze — iOS; 0 reported errors, warnings, test failures, or analysis issues |
| Distribution packaging checks | Opaque 1024 × 1024 icon; exempt-encryption metadata; bundled dependency license notices |
| Internal TestFlight | Build 5 archived and delivered successfully; 0.1.0 (5) shown as Testing; tester confirmed installation and model download started |
| Replacement internal TestFlight | Build 8 archived and delivered successfully from `fd113f2`; 0.1.0 (8) shown as Testing in Personal Device Testing. Tester confirmed updating and reaching “Downloading T5.zip” on 21 November 2026 (Pacific) |
| Benchmark instrumentation tests | 9 unit + 2 UI tests passed locally on iOS 18.4 simulator; 3 report-parser tests passed. These validate measurement code, not model performance |
| Installation checksum regression | Reproduced on Intel Mac in 3 fresh-process pairs; identical SHA-256 with bounded buffer lifetimes. Fixed probe verified the complete 8.9 GB STDiT archive against its pinned digest. See [benchmark record](BENCHMARK_REPORT.md#reproduced-installation-blocker) |
| Memory-fix simulator suite | 11 unit + 2 UI tests passed locally and in Xcode Cloud Build 7; Cloud static analysis also passed with no reported issues |
| Physical setup retry | Exported build 8 journal confirms all 3 archive hashes, all 102 compilation calls, and terminal installation success; resumed install took 236.257 seconds |
| Real-model end-to-end inference | Attempted twice on the target phone; neither completed. No MP4 or visual-quality result |
| Physical iPhone generation | 28 partitions loaded and 27 predictions completed in each attempt. Both logs end inside `stdit3_TDTM_0` prediction after an iOS memory warning; highest recorded footprints 3.38 and 3.19 GB. See [measured results](BENCHMARK_REPORT.md#physical-device-results-from-build-8) |
| Memory-limit candidate validation | 11 unit + 2 UI tests passed locally; 4 report-parser tests passed. Xcode Cloud Build 9 passed Test and Analyze for `8d0cd48`. Build 10 archived and delivered successfully; 0.1.0 (10) is Testing in Personal Device Testing |
| Cooling/background continuation checks | 17 unit + 2 UI tests passed locally; Cloud Build 12 passed Test and Analyze for `0d931e4`, including compilation of the newer background task API path. These are simulator/static checks, not evidence of a physical background GPU grant |
| Remaining-time indicator checks | 20 unit + 2 UI tests passed locally; 5 report-parser tests passed. ETA tests cover unmeasured decoder costs, local timing reuse, restored-step accounting, changing operation durations, and paused labels. Final Cloud and distribution checks pending |
| Build 10 entitlement inspection | Downloaded App Store export contains the Increased Memory Limit entitlement in XML, DER, and the provisioning profile; both entitlement CodeDirectory hashes match. See [package verification and tool limitations](BUILD10_PACKAGE_VERIFICATION.json). Runtime memory allowance and generation success remain unmeasured |

Build success and synthetic encoder fixtures are not diffusion validation. No sample output in this repository is presented as generated video.

Cloud Build 2 tested source revision `3326475bf9e31adeedc0fe094a0cf3d39f238e95` using Xcode 27.2 (27B52), an iPhone 17 Pro Max simulator on iOS 27.2, and macOS Golden Gate 27.2.1. It finished on 20 November 2026 (Pacific time), with a reported four-minute duration and five minutes of compute usage. [View the successful run](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/5cd136c7-903f-4c25-b634-4a19c24eee78/summary).

Build 1 exposed an invalid resource-bundle layout during signing. The tokenizer resources now use SwiftPM processing rather than copying a top-level `Resources` directory. The failure was reproduced locally with codesign, then the corrected bundle passed locally with ad hoc signing and in Cloud. A regression test loads the bundled tokenizer and encodes a real prompt without model downloads.

Cloud Build 3 automatically started on the `main` push of `f76a027e56e5df7d2aa2afd8cd43d882a8e6b415`; its Test and Analyze checks both passed. This confirms push triggering for code/packaging changes.

Cloud Build 6 passed Test and Analyze for benchmark instrumentation source `7b2b82d7a8f64efd6603235b11aad6421f039fb6`. Cloud Build 7 passed all 13 tests and Analyze for checksum-memory fix `fd113f2c1cbbd724247406c587fe1826fac90a68`, with no reported issues. These are simulator and static checks. Exported build 8 logs now verify physical installation and locate the two interrupted generation attempts; a completed video remains unverified.

Cloud Build 9 passed Test and Analyze for `8d0cd48164cad3a135f00bb562394c73623e7cdf`. [Cloud Build 10](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/091564ca-3f49-498b-9f46-c5e631aa9b9c/summary) successfully archived and delivered that revision to internal TestFlight on 21 November 2026 (Pacific). The app-store IPA's version, build number, and embedded source revision match. TestFlight retry instructions were saved. Builds 5 and 8 remain available; update the existing app to preserve its installed model and evidence.

## Automated suite

The eleven unit tests exercise bundled tokenizer loading and prompt encoding, request validation, missing-model failure without a fabricated video, manifest partition coverage, checksum tamper detection and bounded memory, failure/interruption journals, stage-aware memory-warning handling, real AVFoundation MP4 duration/frame rate with library persistence/deletion, and partial-output cleanup. The two UI tests exercise prompt entry, disabled generation before model installation, setup navigation, and the empty library.

## Required real-model checks

1. Compile and load all 102 required partitions. Compare model-declared input/output names, data types, and allowed shapes with the engine.
2. Compare a fixed seed and prompt with the reference implementation. Inspect denoising outputs for finite values and verify temporal decoder ordering and normalization.
3. Generate 2-, 3-, 4-, and 5-second clips. Check encoded frame count, 12 FPS, 256 × 256 resolution, duration, coherent motion, and prompt relevance. Preserve the actual files and metadata as evidence.
4. After model setup, disable network connectivity and generate again. Verify playback, relaunch persistence, Photos permission handling, Files export, deletion, and regeneration.
5. Cancel during prompt encoding, denoising, decoding, and installation. Verify bounded cancellation latency and cleanup. Interrupt with backgrounding and memory pressure; verify recoverable errors.
6. Generate repeatedly on a compatible iPhone 17 Pro Max. Record OS, app/model revision, seed, duration, wall time, peak resident memory with Instruments, temperatures/thermal states, battery impact, and failure logs.

The app's `peakSampledMemoryBytes` is a checkpoint sample, not a continuous peak measurement. It must not replace Instruments data. Thermal/memory guards are preventive checks and do not guarantee protection from OS termination inside a model prediction.

## Public evidence hygiene

Publish source, sanitized test summaries, and intentional generation examples only. Model archives, local caches, signing material, device identifiers, private account details, and raw machine-specific build logs are excluded from this repository.

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
| Real-model end-to-end inference | Not run |
| Physical iPhone generation | Not run |

Build success and synthetic encoder fixtures are not diffusion validation. No sample output in this repository is presented as generated video.

Cloud Build 2 tested source revision `3326475bf9e31adeedc0fe094a0cf3d39f238e95` using Xcode 27.2 (27B52), an iPhone 17 Pro Max simulator on iOS 27.2, and macOS Golden Gate 27.2.1. It finished on 20 November 2026 (Pacific time), with a reported four-minute duration and five minutes of compute usage. [View the successful run](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/5cd136c7-903f-4c25-b634-4a19c24eee78/summary).

Build 1 exposed an invalid resource-bundle layout during signing. The tokenizer resources now use SwiftPM processing rather than copying a top-level `Resources` directory. The failure was reproduced locally with codesign, then the corrected bundle passed locally with ad hoc signing and in Cloud. A regression test loads the bundled tokenizer and encodes a real prompt without model downloads.

## Automated suite

The seven unit tests exercise bundled tokenizer loading and prompt encoding, request validation, missing-model failure without a fabricated video, manifest partition coverage, checksum tamper detection, real AVFoundation MP4 duration/frame rate with library persistence/deletion, and partial-output cleanup. The two UI tests exercise prompt entry, disabled generation before model installation, setup navigation, and the empty library.

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

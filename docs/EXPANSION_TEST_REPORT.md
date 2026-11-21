# Expansion development test report

## Scope

This report covers software validation of prompt styles, explicit crop exports, local settings/metadata and diagnostic controls. It is not a physical iPhone generation or quality benchmark. Image conditioning, continuation, native non-square generation and 24 FPS inference remain unavailable for the reasons in [GENERATION_EXPANSION.md](GENERATION_EXPANSION.md).

## Executed checks

| Check | Observed result |
| --- | --- |
| Local Xcode 16.4 app compilation | Passed |
| Final local regression suite, iPhone 16 Pro Max simulator / iOS 18.4 | 33 unit tests and 4 UI tests passed |
| Xcode Cloud Build 21, iPhone 17 Pro Max simulator / iOS 27.2 | 33 unit tests and 4 UI tests passed; iOS analysis passed, with zero reported warnings, analysis issues, test failures or build errors |
| Tokenizer and all 12 style instructions | Short fixed scene accepted for every style; original scene and effective prompt survive JSON roundtrip |
| Token boundary | A 63-token scene is accepted unchanged with Default; adding Cinematic is rejected without truncation |
| Baseline compatibility | Earlier request JSON remains equal to the new Default request; existing bit-exact checkpoint and recovery tests pass |
| Actual MP4 crop I/O | Both 144 × 256 and 256 × 144 results decode to 24 frames over two seconds; colored bands distinguish cropping from scaling |
| Original preservation | Original file SHA-256 unchanged by both crop exports and a pre-cancelled crop attempt |
| Cancellation cleanup | Pre-cancelled export creates no destination; active mid-export cancellation still requires device acceptance |
| Library compatibility | Legacy records decode; style/effective prompt/seed/parent metadata persist; deleting the original does not delete saved copies |
| UI persistence | Selected style and framing survive app relaunch; unsupported modes remain unavailable |
| Local diagnostics | Styled, non-checkpointed jobs retain their effective prompt and completed-step counts; cancelled journals remain cancelled |
| Static model contract audit | Requested 256 × 448 / 448 × 256 and 120 native frames reject exported input bounds; 56 ST/TDTM blocks lack upstream conditioning inputs |
| Source hygiene | Diff whitespace check and Python script compilation passed; no weights or private device evidence included |

The first crop test used an absolute color threshold inappropriate for a lossy H.264 roundtrip (one red sample was 225 rather than above 230). The corrected test checks dominant-band identity and actual dimensions/frame count, then passed independently and in the full suite. This was a test expectation change, not a model output or performance improvement.

UI screenshots were exported and visually inspected for selected-state visibility, framing disclosure, token count and readable layout. Synthetic test footage and interface illustrations are not presented as AI output.

Local artifacts are retained in ignored `build/LocalFrames-ExpansionFinal.xcresult`, `build/LocalFrames-ExpansionCrop.xcresult`, `build/ExpansionUIScreenshots/` and `build/CapabilityAudit/`. Cloud Build 21 validated the final source, including the prompt-length UI guard, explicit numeric types and extracted style-card view added after the local full-suite build. The targeted local style/framing UI test also passed after the view extraction.

## Cloud validation history

Cloud Build 19 tested the preceding measurement/export-fallback commit `e8876c6`, not the expansion. Its iOS analysis passed, but the newer Swift compiler could not type-check a synthetic pixel-array expression in the test target. The expression now has explicit element-count and Float32 types. Build 20 reached another type-check timeout in the expansion's style-card view; that view is now a separate component with explicit style types. These are compiler compatibility fixes; no inference arithmetic changed.

[Cloud Build 21](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/81235cc0-d3df-4502-b599-38dafbe88829/summary) passed all 37 tests and iOS analysis for `db449195eb25200042db1f992d0eb8a39ed74535`, using Xcode 27.2 (27B52) on macOS Golden Gate 27.2.1 (26B131). The test destination was an **iPhone 17 Pro Max simulator**, not a physical device. No MOVD weights were downloaded or executed by these software tests.

## Development distribution

[Cloud Build 22](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/858d08a1-36a3-4c32-9fd7-95d331bf578f/summary) archived the same `db44919` source. App Store Connect showed both **Archive — iOS** and **TestFlight Internal Testing — iOS** as succeeded. The build's app-store export was listed as 2.1 MB; this excludes the separately installed MOVD weights and is not an installed app-size measurement.

After renewing the expired App Store Connect session, version **0.1.0 (22)** was confirmed as **Testing** in the existing **Personal Device Testing** group (one tester), and the device test instructions were saved. [Build 22 TestFlight details](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/apps/6837604336/testflight/ios/4082b87e-25a6-4485-baa9-ab6459ff6b20).

The separate export-download inspection did not complete, so no independent signed-package/entitlement inspection is claimed for this increment. TestFlight availability does not establish physical installation or successful generation. Update the existing installation without deleting its model or library; no new model download is required.

## Device acceptance still required

Update in place, preserve the installed model and existing videos, then test crop/export/relaunch on the physical iPhone. Run a fresh unchanged two-second baseline before evaluating styles. Enable local diagnostics for Create jobs and compare fixed scene/seed pairs across styles; repeat selected cases at five seconds. Verify Photos and Files export, interruption/cooling behavior, and generation after an Airplane Mode relaunch with Wi-Fi off.

No new physical generation time, runtime memory reduction, GPU/Neural Engine utilization, style quality improvement, or faster sampler result is reported. Use the private device journals for the prior baseline, [OPTIMIZATION_PHASE2.md](OPTIMIZATION_PHASE2.md) for matched runs, and [PRECISION_SCREENING.md](PRECISION_SCREENING.md) for the separate synthetic precision experiment. Original weights and the build-18 rollback tag are retained; optional backend work is unchanged.

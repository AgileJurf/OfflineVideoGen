# Expansion development test report

## Scope

This report covers software validation of prompt styles, explicit crop exports, local settings/metadata and diagnostic controls. It is not a physical iPhone generation or quality benchmark. Image conditioning, continuation, native non-square generation and 24 FPS inference remain unavailable for the reasons in [GENERATION_EXPANSION.md](GENERATION_EXPANSION.md).

## Executed checks

| Check | Observed result |
| --- | --- |
| Local Xcode 16.4 app compilation | Passed |
| Final local regression suite, iPhone 16 Pro Max simulator / iOS 18.4 | 33 unit tests and 4 UI tests passed |
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

Local artifacts are retained in ignored `build/LocalFrames-ExpansionFinal.xcresult`, `build/LocalFrames-ExpansionCrop.xcresult`, `build/ExpansionUIScreenshots/` and `build/CapabilityAudit/`. The final Cloud run must also validate the small prompt-length UI guard and explicit numeric types added after the local test build.

## Cloud validation history

Cloud Build 19 tested the preceding measurement/export-fallback commit `e8876c6`, not the expansion. Its iOS analysis passed, but the newer Swift compiler could not type-check a synthetic pixel-array expression in the test target. The expression now has explicit element-count and Float32 types. This is a test compilation fix; no inference arithmetic changed. The next Cloud run will test the combined candidate before TestFlight distribution.

## Device acceptance still required

Update in place, preserve the installed model and existing videos, then test crop/export/relaunch on the physical iPhone. Run a fresh unchanged two-second baseline before evaluating styles. Enable local diagnostics for Create jobs and compare fixed scene/seed pairs across styles; repeat selected cases at five seconds. Verify Photos and Files export, interruption/cooling behavior, and generation after an Airplane Mode relaunch with Wi-Fi off.

No new physical generation time, runtime memory reduction, GPU/Neural Engine utilization, style quality improvement, or faster sampler result is reported. Use the private device journals for the prior baseline, [OPTIMIZATION_PHASE2.md](OPTIMIZATION_PHASE2.md) for matched runs, and [PRECISION_SCREENING.md](PRECISION_SCREENING.md) for the separate synthetic precision experiment. Original weights and the build-18 rollback tag are retained; optional backend work is unchanged.

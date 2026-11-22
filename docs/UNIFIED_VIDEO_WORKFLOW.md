# Unified 24 FPS workflow, quota display and keyboard fixes

The Create screen offers **12 FPS · offline** and **24 FPS · online finish**. Native MOVD generation remains unchanged. The 24 FPS workflow is limited to the previously validated helper input: two seconds, square 256 × 256, 12 FPS. Longer durations and cropped inputs stay unavailable for smoothing.

## One job, with a required upload review

1. Choose 24 FPS in Create, with online support enabled and compatible settings.
2. MOVD generates locally and saves the original 12 FPS video to Library.
3. The app opens a review of that exact clip. The user must approve its upload to Hugging Face's community `1inkusFace/RIFE` Space. Choosing a frame rate, starting generation or enabling online support is not upload consent.
4. The existing free-only RIFE client checks credentials and quota, uploads the approved snapshot, validates the returned video, and saves a separate 24 FPS copy. The original remains unchanged.

Closing the review, disabling support, a helper failure or relaunch retains a local pending-review reference. Create offers **Review upload & continue** and **Keep 12 FPS only**. Relaunch never restores consent or starts an upload. Each new preview has a new consent identifier. A successful result clears the pending step. No prompt, seed, metadata or other library video is attached to the clip upload. The existing privacy/retention disclosure and no-paid-fallback restrictions remain in force.

This is a coordinated workflow, not a claim of faster local diffusion. It is not an unattended upload: the review remains an intentional user step after generation. Smoothing still needs the app open on Wi-Fi, and a free community helper does not guarantee capacity. Baseline benchmark jobs remain offline and do not automatically enter this workflow.

## Hugging Face allowance

Create's 24 FPS section, Setup and the helper account screen share a quota panel. A manual refresh uses only the existing OAuth profile/billing-status and quota permissions. It shows remaining and total GPU time, the provider's reset date when present, and the reading's timestamp. An automatic refresh follows an approved smoothing attempt while the app is foregrounded and support remains enabled.

The account gate remains free-only: paid or unverifiable accounts and memberships are blocked. An exhausted balance can be displayed without authorizing an upload. Each upload independently rechecks current eligibility and available quota. The displayed balance is never used as cached permission. Failed refreshes retain a clearly dated last reading. Disconnection clears the display; online support off prevents refreshes and cancels in-flight checks.

The helper currently requests at least 90 GPU-seconds of allowance to admit a job. This is not a measured per-clip cost or a promised count of jobs. Quota is shared with the account's other ZeroGPU Spaces. Anonymous requests use a shared allowance; no personal balance is invented for them. Current free-account documentation states five minutes per daily window, resetting 24 hours after first use.

Primary references: [Hugging Face quota API](https://huggingface.co/docs/huggingface_hub/main/guides/manage-spaces#track-your-zerogpu-quota), [ZeroGPU tiers](https://huggingface.co/docs/hub/spaces-zerogpu). The API's `base`, `current`, `resetsAt` and optional run limit are validated before display. Malformed or paid responses fail closed.

## Create and Setup layout

Create uses separate cards for the scene, visual style, duration/framing, repeatable settings and frame-rate finish. Current work and unfinished smoothing jobs appear at the top. Every explanatory caption stays inside its associated card or toggle label. Model management, online assistance, background availability and developer tools are separate Setup sections; detailed baseline controls have their own screen.

Prompt and both numeric seed fields have a keyboard **Done** accessory. Focused screens also show a navigation-bar hide-keyboard control. Beginning work, scrolling, leaving the screen and switching tabs dismiss the keyboard without changing the input.

## Background generation

The user's earlier phone journals recorded `gpuSupported=false` and `registered=false`; the new recording still showed the foreground fallback. This is not evidence of successful background GPU execution.

The updated path registers the exact identifier immediately before each continued-processing request, instead of registering only a wildcard handler. The plist still permits the dynamic suffix, and the GPU entitlement is preserved. Registration handlers capture only a weak reference, not model buffers. The app shows whether GPU background access is unsupported, task registration was rejected, submission failed, the launch callback timed out, or execution was granted. Grants alone enable background inference; thermal pauses remain enforced. Expiration revokes permission immediately. The ten-second foreground fallback prevents a missing system callback from stranding the job.

This change follows Apple's [continued-processing workflow](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados). iOS still controls eligibility and duration. Force-quitting ends processing. Where background GPU access is unavailable, the app safely pauses when minimized and resumes on return; it cannot promise uninterrupted generation. Saved baseline checkpoints remain the recovery option after termination.

## Validation boundaries

Automated tests use synthetic media and stubbed helper responses to cover saved-output-to-review handoff, relaunch recovery, fresh consent, unsupported combinations, quota exhaustion/reset parsing, cancellation/offline gates, original preservation and a decoded 48-frame result. These fixtures do not substitute for real diffusion or claim a new physical-device benchmark. The live helper's native Simulator integration was separately validated for Build 35; this update retains that client and model.

Local UI checks cover explicit dismissal of the prompt keyboard and both numeric keyboards, navigation, offline model gating, style/framing persistence and the 24 FPS review explanation. Xcode Cloud compiles the newer background API and runs Simulator regression checks. A physical iPhone 17 Pro Max test is still required for the new UI, whole generation-to-review handoff and actual background GPU grants. The current Mac cannot attach to this phone's newer beta OS.

Rollback: `baseline/testflight-build-35` retains the previous released implementation. MOVD assets, sampler, precision, thermal control, local originals and export paths are preserved. No Vercel backend or model package changes are part of this update.

Local validation on 21 November 2026: 65 unit/integration tests passed; the live-upload test was intentionally skipped. All seven UI tests passed across the final regression and a focused keyboard rerun. The initial numeric-keyboard assertion ran during the dismissal animation; the final test waits up to five seconds for keyboard disappearance and passed all three fields. Results are retained locally in `build/Workflow36/FinalRegression.xcresult` and `build/Workflow36/KeyboardFinal.xcresult`. No personal clip was uploaded and no new live GPU job was used for these checks.

Final source `d9537b4c0a9c1654fd985701904ea4fcbca4a95a` also closes the workflow review when reusing a completed video's settings. Its focused integration test passed in `build/Workflow36/ReuseWorkflow.xcresult`. [Xcode Cloud Build 37](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/c33c6785-9b52-4c69-881b-40ca464688e9/summary) passed Test and Analyze on Xcode 27.2: 65 unit/integration tests and seven UI tests passed; one live-upload test was intentionally skipped. The final Cloud UI pass includes keyboard dismissal, offline defaults and unified-job controls.

Separate research records cover [trained style compatibility](TRAINED_STYLE_ADAPTERS.md) and [alternative engines](MODEL_ALTERNATIVES.md). Neither enables new weights or changes this release's generation engine.

Released as **0.1.0 (38)** to Personal Device Testing on 21 November 2026. Xcode Cloud archive and TestFlight delivery succeeded for `d9537b4`; App Store Connect showed Testing with one tester, and the What to Test notes were saved. Release source is preserved as `baseline/testflight-build-38`.

# Internal TestFlight beta

Local Frames is an experimental native video diffusion app with MOVD / Open-Sora and an optional Neodragon engine. Genuine offline 2-second MOVD generation has completed on the physical iPhone 17 Pro Max. Neodragon, new model settings and optional postprocessing still require their own device validation.

## Current release

**0.1.0 (41)** is available in **Personal Device Testing**, released on 21 November 2026. It adds optional Neodragon model installation, model selection in Create, and a **2–9 second** duration selector for that engine at native **512 × 320 / 24 FPS**. MOVD retains its supported 2–5 second range. The redundant “While the app is minimized” Setup section is removed. Neodragon generation runs locally after installation and does not require the online smoothing helper.

Xcode Cloud Build 40 passed **81 tests and Analyze**, with six intentional skips (five model/reference fixture tests and one separately authorized live-upload test). Build 41 archived and reached TestFlight **Testing**, with saved testing notes. A complete native macOS CPU run produced a genuine two-second Neodragon video containing 48 distinct frames. This is not physical-iPhone validation: a complete nine-second generation and iPhone acceptance remain pending. See [the implementation and measured test report](NEODRAGON_IMPLEMENTATION.md).

**0.1.0 (38)** remains a rollback option. Its combined online 24 FPS workflow, per-clip consent, keyboard dismissal, Hugging Face quota display, grouped screens and background task handling are preserved. See [the workflow report](UNIFIED_VIDEO_WORKFLOW.md). No trained style adapter is included in Build 41.

## Optional Neodragon setup and acceptance

1. Update to **0.1.0 (41)**. In **Setup**, choose the optional Neodragon download and confirm it. The eight archives total **7,881,071,452 bytes (about 7.88 GB)**. Allow **32,212,254,720 bytes (about 32.21 GB / 30 GiB)** free during installation; this is a conservative allowance, not measured installed storage. Keep the app open on Wi-Fi while it verifies and compiles the package.
2. In **Create**, select Neodragon after installation. Start with **2 seconds**, Default style, seed **42**, and “A small sailboat glides across a calm lake at sunrise.” Enable Airplane Mode and explicitly turn Wi-Fi off for the offline check.
3. Retain the completed MP4, local journal and generation metadata. Check playback, motion, export and library persistence. Record generation time, peak memory, thermal pauses and any failure.
4. Only after the short test succeeds, test longer selections through **9 seconds**. Nine seconds targets 216 frames at 24 FPS. Its longer tensor range passed component checks; a complete nine-second output has not yet been validated.

The existing MOVD installation and videos remain separate. Neodragon can be removed independently. Its thermal/background pause retains the active job in memory; it does not yet recover an interrupted Neodragon job after force quit or process termination. MOVD's saved baseline recovery is preserved.

## Optional 24 FPS smoothing beta

**0.1.0 (35)** was released on 21 November 2026 and remains a rollback option. It fixes the earlier Build 31 connection with optional free-account sign-in and verified queue handling. Its live native Simulator test completed a real 24 FPS copy; physical-iPhone acceptance remains pending. See the [current connection test report](SMOOTHING_CONNECTION_TEST.md) for measured results and the release record.

Enable **Setup → Online support and model updates → Enable online support**, then choose a compatible 2-second square 12 FPS clip. Preview it and approve that exact upload to Hugging Face’s community `1inkusFace/RIFE` helper. An action is also available in compatible video previews while support is enabled. No clip is uploaded by enabling the switch or finishing generation. Every retry requires another review and approval.

For the updated connection, open **Helper account and free quota**, connect your free personal Hugging Face account, approve on Hugging Face’s website, return to the app, and tap **Finish connecting**. The optional 8-hour connection is stored in device Keychain. Its permissions cover profile, billing status/usage and memberships; the app reads only eligibility and quota. Paid, billing-enabled, organization-linked or unverifiable accounts are blocked before upload. Each clip still requires its own consent.

Keep the app foregrounded on Wi-Fi. Anonymous shared free quota remains available but may be exhausted; connected free accounts use their included allowance. No credits are purchased and no paid fallback is used. Cancellation/backgrounding stops local work without automatically retrying, but cannot guarantee that a clip already sent is deleted from the helper. Its retention period is unspecified. The original video is preserved, and a successful result is separately saved as 48 frames at 24 FPS for exactly two seconds. This is optional frame interpolation, not faster diffusion or higher-resolution generation.

For the device acceptance pass, compare both saved clips, replay and export each, then turn support off and verify library/export and offline generation in Airplane Mode. Do not delete the working original or installed model. See [the integration report](ONLINE_SMOOTHING.md).

## Install and prepare MOVD

1. Install Apple's TestFlight app on the iPhone, then accept the invitation sent to the internal tester's Apple account and install **LocalFrames** (displayed on the Home Screen as **Local Frames**).
2. Allow at least **50 GB of free storage** for model setup. The three model archives total about **14.1 GB**; extraction and Core ML compilation require additional temporary space. The allowance is conservative, not a measured installed size.
3. Connect to Wi-Fi, open **Setup**, and install the model. Keep the app open while downloading and compiling all required partitions. Downloads may resume when supported by the server; interrupted compilation starts again.
4. Wait for setup to finish before attempting generation. Keep the device cool and keep the app in the foreground.

## First offline MOVD test

1. After setup completes, enable Airplane Mode and explicitly turn Wi-Fi off.
2. Enter a short prompt such as “A small sailboat glides across a calm lake at sunrise.” Select **2 seconds**, then generate.
3. Record whether the run finishes, its elapsed time, the last displayed stage if it fails, and any error message. Do not treat an installed model or an empty video file as successful generation.
4. If a clip completes, inspect motion and prompt relevance, replay it, relaunch the app and check persistence, then try Photos saving and Files export while still offline.
5. After the first success, test longer clips, cancellation, and repeated generation. Use TestFlight feedback for screenshots and crash reports; retain the generated MP4 and its metadata as evidence.

The target output is 256 × 256 at 12 FPS. Even the 2-second option runs the full temporal denoising sequence before saving a shorter decoded prefix, so it is not expected to proportionally reduce inference memory or time.

## Prompt and output handling

The app has no prompt blocklist, moderation service, prompt rewriting service, or output-content classifier. It trims surrounding whitespace and uses the selected model's local tokenizers. MOVD's input limits are 500 characters and 63 model tokens. Neodragon checks all four 77-slot CLIP limits and its 128-slot T5 limit, including special tokens; it rejects overflow rather than silently truncating. Optional visual style instructions are included in those checks. Output validation checks tensor shape, finite pixel values, and file integrity.

The upstream model weights are unchanged. Absence of app-level filtering does not establish how the pretrained model will respond to every prompt or guarantee output quality. Storage, memory, temperature, and cancellation checks remain enabled for reliable device testing.

## Distribution

The **TestFlight Beta** Xcode Cloud workflow uses a manual start condition on `main`. It archives the LocalFrames scheme with **TestFlight (Internal Testing Only)** preparation and delivers successful archives to **Personal Device Testing**. Build 41, version 0.1.0, reached Testing with one internal tester and saved testing notes. The released app source is `ea23bcfad656c43d00dc494a3ae844cc2c9a26cc`. Build 38 remains preserved at `baseline/testflight-build-38` (`d9537b4c0a9c1654fd985701904ea4fcbca4a95a`), and Build 35 at `baseline/testflight-build-35`. Public source availability does not make the TestFlight beta publicly installable.

For instrumented device testing, follow the [benchmark record and procedure](BENCHMARK_REPORT.md). The benchmark controls are added after Build 5; use the newer instrumented beta when available. Complete active setup before updating.

See [Xcode Cloud](XCODE_CLOUD.md) and the [validation record](VALIDATION.md) for observed build results. Device inference remains a separate validation gate.

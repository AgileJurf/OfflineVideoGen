# Internal TestFlight beta

Local Frames is an experimental native MOVD / Open-Sora video diffusion app. Genuine offline 2-second generation has completed on the physical iPhone 17 Pro Max. New model settings and optional postprocessing still require their own device validation.

## Optional 24 FPS smoothing beta

Enable **Setup → Online support and model updates → Enable online support**, then choose a compatible 2-second square 12 FPS clip. Preview it and approve that exact upload to Hugging Face’s community `1inkusFace/RIFE` helper. An action is also available in compatible video previews while support is enabled. No clip is uploaded by enabling the switch or finishing generation. Every retry requires another review and approval.

Keep the app foregrounded on Wi-Fi. Anonymous shared free quota may be exhausted; no credentials, credits or paid fallback are used. Cancellation/backgrounding stops local work without automatically retrying, but cannot guarantee that a clip already sent is deleted from the helper. Its retention period is unspecified. The original video is preserved, and a successful result is separately saved as 48 frames at 24 FPS for exactly two seconds. This is optional frame interpolation, not faster diffusion or higher-resolution generation.

For the device acceptance pass, compare both saved clips, replay and export each, then turn support off and verify library/export and offline generation in Airplane Mode. Do not delete the working original or installed model. See [the integration report](ONLINE_SMOOTHING.md).

## Install and prepare

1. Install Apple's TestFlight app on the iPhone, then accept the invitation sent to the internal tester's Apple account and install **LocalFrames** (displayed on the Home Screen as **Local Frames**).
2. Allow at least **50 GB of free storage** for model setup. The three model archives total about **14.1 GB**; extraction and Core ML compilation require additional temporary space. The allowance is conservative, not a measured installed size.
3. Connect to Wi-Fi, open **Setup**, and install the model. Keep the app open while downloading and compiling all required partitions. Downloads may resume when supported by the server; interrupted compilation starts again.
4. Wait for setup to finish before attempting generation. Keep the device cool and keep the app in the foreground.

## First offline test

1. After setup completes, enable Airplane Mode and explicitly turn Wi-Fi off.
2. Enter a short prompt such as “A small sailboat glides across a calm lake at sunrise.” Select **2 seconds**, then generate.
3. Record whether the run finishes, its elapsed time, the last displayed stage if it fails, and any error message. Do not treat an installed model or an empty video file as successful generation.
4. If a clip completes, inspect motion and prompt relevance, replay it, relaunch the app and check persistence, then try Photos saving and Files export while still offline.
5. After the first success, test longer clips, cancellation, and repeated generation. Use TestFlight feedback for screenshots and crash reports; retain the generated MP4 and its metadata as evidence.

The target output is 256 × 256 at 12 FPS. Even the 2-second option runs the full temporal denoising sequence before saving a shorter decoded prefix, so it is not expected to proportionally reduce inference memory or time.

## Prompt and output handling

The app has no prompt blocklist, moderation service, prompt rewriting service, or output-content classifier. It trims surrounding whitespace and sends the prompt through the local tokenizer to MOVD. The input limits are 500 characters and 63 model tokens. Output validation checks tensor shape, finite pixel values, and file integrity.

The upstream model weights are unchanged. Absence of app-level filtering does not establish how the pretrained model will respond to every prompt or guarantee output quality. Storage, memory, temperature, and cancellation checks remain enabled for reliable device testing.

## Distribution

The **TestFlight Beta** Xcode Cloud workflow uses a manual start condition on `main`. It archives the LocalFrames scheme with **TestFlight (Internal Testing Only)** preparation and delivers successful archives to **Personal Device Testing**. Build 5, version 0.1.0, successfully reached Testing and the internal tester was invited. Public source availability does not make the TestFlight beta publicly installable.

For instrumented device testing, follow the [benchmark record and procedure](BENCHMARK_REPORT.md). The benchmark controls are added after Build 5; use the newer instrumented beta when available. Complete active setup before updating.

See [Xcode Cloud](XCODE_CLOUD.md) and the [validation record](VALIDATION.md) for observed build results. Device inference remains a separate validation gate.

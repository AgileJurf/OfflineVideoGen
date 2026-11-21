# Optional online 24 FPS smoothing

Implementation dated 21 November 2026. Genuine MOVD generation remains entirely on the iPhone. This beta adds an optional remote interpolation stage after a video has been generated and saved. It makes no claim of faster diffusion or universally improved visual quality.

## Supported workflow

1. Enable online support in Setup. This alone makes no network request.
2. Choose an original 2-second, 256 × 256, 12 FPS library clip, or use its preview action. Longer clips, crops and already-smoothed copies are excluded from this initial tested contract.
3. The app copies that exact MP4 into a private temporary directory, decodes and validates all 24 frames, checks dimensions, timestamps, duration and absence of audio, and calculates SHA-256. The consent preview plays that frozen copy.
4. Review the destination and privacy disclosure, explicitly agree, then choose Upload this clip & create 24 FPS copy. Consent is bound to that preview and consumed before the first request. Toggle changes, errors, cancellation and retries cannot reuse it.
5. The app uploads only that MP4 as `clip.mp4` directly to `https://1inkusface-rife.hf.space`. Prompts, seeds, filenames, library sidecars, diagnostics and other files are not attached. Visible content inside the approved video itself is necessarily sent.
6. The helper uses RIFE 2x interpolation, native output FPS, MP4, with boomerang disabled. The running third-party weights are service-managed and not independently pinned. The app validates the output as 47 or 48 decoded frames at 24 FPS. If 47, it holds the last frame for another 1/24 second, then verifies the saved result is 48 frames and exactly 2 seconds. Endpoint holding is recorded explicitly, not described as a newly inferred frame.
7. Save under a new library ID with parent ID and interpolation provenance. Original generation time/metrics remain distinct from smoothing time (which includes transfer and queueing). Original MP4 bytes are untouched. Either item can be exported or deleted independently. Regenerate uses the original local 12 FPS settings and never repeats an upload.

## Privacy, free access and failure handling

- The destination is a community Space, not the developer’s Vercel backend. The full approved clip and network metadata reach Hugging Face and its Space operator. Remote cache retention/deletion is not guaranteed. The consent view links the provider’s privacy policy and warns that local cancellation may not stop remote processing or delete an uploaded clip.
- Requests use a separate ephemeral, cookie-free, credential-free URLSession. No browser session, account token, credit purchase, subscription or paid fallback exists. Wi-Fi only; expensive/constrained networks and redirects are refused. Anonymous access uses shared free capacity and may fail despite browser access working. Browser login is not imported into the app.
- Upload/result files are capped at 8 MiB. JSON and event responses are separately bounded. HTTPS output URLs must remain on the exact helper host and its MP4 file endpoint. Response type, HTTP status, path and event schema are checked. Every network resource has a 180-second maximum; no retry loops or background resumption.
- Cancellation, backgrounding, disabling support and memory pressure stop local work. Temporary copies are removed after the operation or on the next launch after termination. The original remains usable if any stage fails. The app does not expose raw remote error bodies or URLs to diagnostics.
- No media traverses Vercel. Existing support configuration, diagnostics retention, model manifests, model weights, download behavior, sampler, precision and Core ML execution remain unchanged.

Hugging Face currently documents two minutes of anonymous shared ZeroGPU time and five minutes for free authenticated accounts; paid tiers can automatically consume prepaid credits. The native app deliberately uses only anonymous requests and never offers that paid path. These quotas are not a service availability guarantee. [ZeroGPU terms](https://huggingface.co/docs/hub/spaces-zerogpu), [Space API documentation](https://huggingface.co/docs/hub/spaces-api-endpoints), [helper source](https://huggingface.co/spaces/1inkusFace/RIFE/blob/main/app.py), [provider privacy](https://huggingface.co/privacy).

## Reproducible validation

Synthetic media fixtures are bundled **only in the test target**, not the shipped application. They originate from the [recorded GPU experiment](benchmarks/rife-synthetic-2026-11-21/experiment.json). Automated tests do not upload personal clips or call the real helper.

`SmoothingTests` covers per-clip consent, disabled support, one-use consent after failures, snapshot selection and tampering, full upload/job/event/download protocol with recorded synthetic responses, actual video decoding and duration normalization, independent library storage and deletion, original SHA preservation, invalid output URLs/events, missing credentials, no automatic requests and cancellation. Existing model, checkpoint, crop, tokenizer, library and UI tests remain regression gates. Network mocks validate client behavior; they are not evidence of live helper availability.

The full local regression run passed **56/56 tests**: 33 existing engine/library tests, 10 support tests, 8 smoothing tests and 5 UI tests, on the iOS 18.4 iPhone 16 Pro Max simulator with Xcode 16.4. The unit pass took 29.25 seconds and the UI pass 80.10 seconds. Existing backend tests passed **10/10**. These are software regression results, not iPhone 17 Pro Max inference/performance measurements. Prior successful browser interpolation is evidence for the model/helper, not proof that this new iOS integration has completed on a physical device.

Manual Simulator review confirmed the exact synthetic clip renders in the consent preview, Upload starts disabled, explicit consent enables it, and leaving/reopening the same clip resets consent and disables Upload again. The review made no upload, and online support was turned off afterward. The final local app build passed after the comparison-view labels were updated.

Initial Cloud Build 28 passed 55/56 tests. Its UI failure queried the off-screen model-update button, which the newer iOS Form snapshot omitted. The test now scrolls each control into view before inspection; the corrected test passed locally (46.47 seconds). Cloud also identified a nested progress capture warning. The progress callback now consistently shares the operation’s bounded lifetime, matching the existing export callbacks; `finish()` releases the task. Neither correction changes inference or helper settings.

**Xcode Cloud Build 30 passed 56/56 tests** on the iPhone 17 Pro Max simulator running iOS 27.2, using Xcode 27.2 (27B52). The corrected source is `6b92c0ce03b61ef093b4141f93a995bec10e29a4`. Build, test and analysis completed with no reported compiler warnings, errors or analysis issues. The same source was selected for the manual TestFlight release workflow. These simulator tests validate the app integration; physical-device smoothing completion remains pending.

**TestFlight 0.1.0 (31) was released on 21 November 2026.** Xcode Cloud Build 31 archived that exact source and completed its internal TestFlight delivery at approximately 2:58 PM Pacific. App Store Connect showed **Testing**, assigned to **Personal Device Testing**, with one internal tester. The per-clip consent instructions, free anonymous helper limits, and pending physical-device validation were saved in What to Test. The release source is preserved by `baseline/testflight-build-31`. The existing Build 25 remains available as the prior rollback option.

A single live anonymous test of the **actual native HTTP/media implementation**, compiled for macOS, ran at 22:15 UTC on 21 November 2026. It uploaded only the committed synthetic moving-shapes fixture and reached the job stage, but returned no output (`unavailable`, 1.069 seconds to failure). This is a service availability failure, not a latency improvement. No credentials or personal clip were sent. The earlier anonymous official-client probe explicitly reported quota refusal; this native response did not identify a more specific cause. A signed-in browser success does not prove anonymous native availability.

The native probe deliberately requires an explicit synthetic-upload flag and makes no retries:

```sh
xcrun swiftc -module-cache-path build/NativeSmoothingModuleCache -parse-as-library \
  LocalFrames/Services/RIFEClient.swift LocalFrames/Services/VideoSmoothing.swift \
  scripts/probe_native_smoothing.swift -o build/probe-native-smoothing
build/probe-native-smoothing --confirm-synthetic-upload
```

## Rollback and remaining limits

Turn online support off to keep using the unchanged offline engine. `baseline/testflight-build-25` preserves the previous app source; the working MOVD model is unchanged. No new model or package dependency is downloaded into the app. The service can change, exhaust quota, sleep or disappear, and optical-flow interpolation can introduce artifacts around occlusion or large motion. Native 24 FPS diffusion, 3–5 second smoothing, upscaling, remote transformer assistance and performance acceleration are not enabled by this change.

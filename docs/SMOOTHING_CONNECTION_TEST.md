# Free helper connection: live app test

21 November 2026. The corrected iOS app completed a real authenticated request to the community `1inkusFace/RIFE` Space, validated the returned video, and saved a separate library copy. This was an app-hosted test on the iOS 18.4 iPhone 16 Pro Max Simulator with Xcode 16.4. It is not physical iPhone 17 Pro Max validation or a MOVD speed benchmark.

## Failure and correction

Build 31's anonymous `/call/interpolate_video` request returned an opaque error. The official Gradio client exposed the cause: the helper requested 90 GPU-seconds while the shared anonymous allowance had only 61 seconds left. Browser sign-in does not authenticate native requests.

The update adds optional Hugging Face device OAuth using a registered public client, with no app secret. The provider's permission covers public profile, billing status/usage and memberships; Local Frames reads only free-account eligibility and GPU quota. Eight-hour tokens live in this device's Keychain and are excluded from backups and diagnostics. Free status, no billing access, no memberships and sufficient included quota are checked before each approved upload. Expired, paid or unverifiable connections fail before sending video. No paid fallback, credits purchase, identity rotation or automatic retry is implemented.

The helper's `/config` resolves the named interpolation dependency instead of hardcoding a function index. `/gradio_api/queue/join` and its SSE stream provide completion and classified quota errors. The actual device-code response also uses the official `hf.co` verification alias; the app accepts that exact path and presents the canonical Hugging Face page. Requests and result URLs remain restricted to explicit HTTPS endpoints, with no redirects or cookies.

## Measured live result

The user explicitly approved account connection and this fabricated moving-shapes test. No personal clip, prompt, seed, journal or payment action was involved. The test started at 23:38:48 UTC and passed at 23:38:59 UTC. The approval page and native account screen both showed a completed connection before testing.

| Measurement | Observed result |
| --- | --- |
| Source | 24 frames, 12 FPS, 256 × 256, 2.000 seconds |
| Helper settings | RIFE 2×, native FPS, MP4, boomerang off |
| Raw returned frames | 47 |
| Final local copy | 48 decoded frames, 24 FPS, 256 × 256, 2.000 seconds |
| Endpoint correction | One explicit terminal hold of 1/24 second |
| Complete smoothing operation | 9.509 seconds, one run |
| Timing includes | Eligibility/quota, configuration, upload, queue, interpolation, download, local normalization |
| Timing excludes | Initial local preview preparation and final library save |
| App test including preparation/save/assertions | 10.641 seconds |
| Separate library items | Two; derivative references original |
| Original integrity | SHA-256 unchanged |
| Distinct intermediate motion frames | 23 of 23 |
| Intermediate position error | Mean 0.106 pixels; maximum 0.330 pixels |
| Timestamp error | Zero relative to exact 1/24-second frame times |

The output's added motion is measured from an orange rectangle translating eight pixels per source frame. This narrow test does not establish natural-scene quality, occlusion handling, thermal behavior or iPhone latency. The terminal held frame is not represented as an extra inferred frame. No inference settings or model weights changed.

Public evidence contains synthetic content only: [app measurements](benchmarks/rife-native-2026-11-21/app-test.json), [decoded motion measurements](benchmarks/rife-native-2026-11-21/motion-validation.json), [real native result](benchmarks/rife-native-2026-11-21/native-24fps.mp4), [source fixture](benchmarks/rife-synthetic-2026-11-21/source-12fps.mp4). The original XCTest bundle is retained locally under `build/SmoothingConnectionFix/LiveHelper.xcresult`; credentials and account details are absent from published evidence.

## Reproduction

For an offline check of the saved result:

```sh
xcrun swiftc -module-cache-path build/HybridProbe/ModuleCache -parse-as-library \
  scripts/verify_interpolation_fixture.swift -o build/HybridProbe/verify-interpolation
build/HybridProbe/verify-interpolation \
  docs/benchmarks/rife-synthetic-2026-11-21/source-12fps.mp4 \
  docs/benchmarks/rife-native-2026-11-21/native-24fps.mp4 \
  build/HybridProbe/native-recheck.json
```

For another live test, first build/install the app on a dedicated Simulator, explicitly connect an eligible free account through Setup → Online support → Helper account and free quota, and finish the connection. Do not copy tokens from the browser or paste them into a command. Run `xcodebuild build-for-testing` with the LocalFrames scheme and that Simulator destination. Copy the generated `.xctestrun` file beside its original so `__TESTROOT__` paths remain valid. In the copy only, set `LocalFramesTests.EnvironmentVariables.LOCALFRAMES_LIVE_SYNTHETIC_SMOOTHING` to `1`. Then invoke:

```sh
xcodebuild test-without-building -xctestrun PATH_TO_EXPLICIT_LIVE_COPY \
  -destination 'platform=iOS Simulator,id=YOUR_DEDICATED_SIMULATOR' \
  -only-testing:LocalFramesTests/SmoothingTests/testLiveHelperSavesSynthetic24FPSCopyInAppLibrary \
  -resultBundlePath build/LiveHelperRepeat.xcresult
```

This is an explicit upload of the bundled synthetic fixture, using the same `AppModel`, account, HTTP client, media validation and library implementation as the app. The test attaches its MP4 and measurement JSON on success. Without the environment gate, it is skipped; normal regression/Cloud tests perform no GPU job. Do not repeatedly retry exhausted quota. Disconnect the dedicated test account afterward.

## Regression and remaining acceptance

The account tests cover eligibility, quota, expiry, identity consistency, overscoped grants, device polling, cancellation and secure-store behavior. Smoothing tests cover consent, token endpoint restrictions, queue parsing, quota errors, original integrity, output decoding, independent library storage, cancellation and offline-toggle behavior. Local regression passed 64 tests: 59 unit/integration tests in 27.49 seconds and five UI tests in 139.26 seconds. The explicitly gated live test was skipped during ordinary regression and passed separately as recorded above. Backend tests passed 10/10. The first combined run completed all unit tests but its UI pass was interrupted after the live setup had left support enabled; after disconnecting the temporary account and restoring support to off, the complete UI rerun passed. This setup failure is retained in the local result bundle. Xcode Cloud [Build 34](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/ac734b25-3bcc-45f9-976e-4cabda3eb326/summary) succeeded for `1d7adfc7bd522e993387e21d08202bcebec726e7` using Xcode 27.2 (27B52). Its iPhone 17 Pro Max / iOS 27.2 simulator report shows 64 passed, zero failed and the single live-upload test intentionally skipped. Test and Analyze succeeded. The test-stage warning denotes that skipped test; no real GPU request was made by CI.

The available Mac still cannot mount developer services for the physical iPhone's newer iOS beta. The new helper therefore still requires TestFlight acceptance on that phone: connect a free account, approve a selected compatible clip, confirm both copies play/export, and turn support off to verify offline library/export and unchanged local generation. No physical-device success is claimed for this update.

Rollback: `baseline/testflight-build-31` preserves the preceding app, and `baseline/testflight-build-25` preserves the earlier release. Installed MOVD weights, inference, checkpoint recovery, original videos and export remain unchanged. Disabling online support makes the helper unavailable without affecting local generation.

## Released build

**TestFlight 0.1.0 (35)** was confirmed Testing in **Personal Device Testing**, with one internal tester, on 21 November 2026 at approximately 4:05 PM Pacific. [Cloud Build 35](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/xcode-cloud/products/0520A902-29E3-4557-8FD7-6AA8988BCCD7/builds/7da51392-7044-4686-b6e0-31d60fd2c0df/summary) successfully archived and delivered the exact validated app source `1d7adfc7bd522e993387e21d08202bcebec726e7`. [The TestFlight build](https://appstoreconnect.apple.com/teams/74071065-09b9-4ec3-892d-f3f4fd3eb8ab/apps/6837604336/testflight/ios/97a9d444-523a-45e5-9d45-bd5f73c05084) has saved connection, consent and physical-device acceptance instructions. The app source is preserved at `baseline/testflight-build-35`; Build 31 remains the preceding rollback. The public Vercel privacy disclosure was checked after deployment and includes the actual billing-status/usage scope, Keychain storage and per-clip consent. No media storage or paid backend infrastructure was added.

# Neodragon studio migration

Development branch: `feature/snapdragon-studio`. Prepared 27 November 2026; physical-device acceptance of this branch is pending. It extends the `feature/liquid-glass` foundation without merging into `main`.

## Engine identity and weight decision

“Snapdragon” in the request refers to the currently integrated **Neodragon** checkpoint from Qualcomm AI Research. The release retains weights `5bdc87a4895a4fd148ca14c03181345d278d1040`, source `d2abbe99f46577c4e1db682ad3c26832ec0c23b9`, and package `neodragon-coreml-9s-v1`. No new training or quantization has taken place. The package contains 168 partitions; the diffusion schedule and numerical operations remain unchanged.

Upstream publishes `diffusion_transformer_320p_multistep_t2v` with a matching `context_adapter_multistep_t2v`. This is a research candidate, not a selected replacement or verified improvement. Its monolithic generation path needs a separate conversion and scheduler/conditioning compatibility audit. Upstream's aggregate benchmark is not an iPhone measurement and does not establish superiority over the working hybrid variant. No verified compatible pretrained Anime, Photorealism or Cinematic adapter was found. Generic SDXL/FLUX adapters are not interchangeable with this motion transformer.

Primary references: [official code](https://github.com/qualcomm-ai-research/neodragon), [official weights](https://huggingface.co/Qualcomm-AI-Research/Neodragon/tree/main). Neodragon has BSD-3-Clause-Clear and Qualcomm Responsible AI terms; component licenses are retained in the model distribution and `tools/neodragon/`. Retained shared utility attribution is preserved even though the earlier model runtime is removed.

## UI and styles

Native SwiftUI glass effects, container and glass button styles compile only with a supporting compiler/SDK and run on iOS 26+. iOS 18 retains native navigation with material fallbacks. Reduce Transparency and the app's Reduced Visual Effects preference use opaque surfaces; motion effects respect Reduce Motion. Glass is concentrated in controls and overlays.

Create uses a real local video thumbnail or an empty canvas, expandable prompt editing, duration, selected prompt style and advanced seed settings. Library offers search, grid/list layouts, chronological ordering, playback, settings reuse, Photos export and deletion. AVKit supplies accessible playback/scrubbing controls. Models shows the actual active engine. Settings separates appearance, generation, storage, offline information, privacy and Frame Lab. Unsupported modes are absent.

58 built-in style definitions cover realistic, animation, artistic, genre and environmental directions. They are structured prompts, not adapters or filters. Custom styles store aesthetic, palette, lighting, camera and motion fields locally. Names can be edited, styles duplicated/deleted, favorites saved and recently used styles recalled. Video metadata contains a style snapshot, so editing a preset does not rewrite earlier generations. Thumbnails are explicitly illustrative local artwork, not model-generated examples. Each style still requires visual evaluation on device.

## Safe retirement

The migration inventory was checked against the Build 44 installer. It removes exact retired partition/package names within the former Models installation, staging, rollback and extraction roots; the three old archives and resume data; verified old installation markers; known online-support preferences/catalog; UUID-named smoothing work; and identified old baseline recovery files. It does not traverse symlinks or remove broad Documents, Library, OptionalModels or shared OS caches. Unknown paths are retained and reported.

A private atomic journal records each pending removal before deleting it and credits completion afterward. Restart recovers an interrupted item without counting it twice. The report includes file bytes and allocated bytes removed plus available volume space before/after. Those measurements differ under filesystem sharing or unrelated system activity. Shared OS caches cannot safely be attributed to one model and are not claimed as reclaimed.

The existing Neodragon installation path is unchanged. Generated videos, imported assets, historical metadata, preferences and projects remain intact. Old crop/interpolation provenance is decoded only for library compatibility; there is no active interpolation service or hidden retired inference engine.

## Files and diagnostics

Files exposes the app's Documents root as Local Frames, containing Videos and Benchmarks. Automatic publication respects exported files moved/deleted in Files. An explicit export restores missing copies; filename collisions preserve user edits. The private library remains authoritative. Journals may contain prompts and should be reviewed before manual sharing. There are no automatic uploads.

The job log displays actual engine/partition events in a 200-entry memory-bounded buffer, refreshed at most twice per second. Full journals remain on disk. Motion estimates use measured completed units and exclude known pauses; loading, decoding and total-job estimates are not fabricated. Memory alerts now retain the last visible stage. Thermal and background protections remain active.

## Testing and cloud configuration

Local Intel validation uses Xcode 16.4 / iOS 18.5 SDK and the iPhone 16 Pro Max iOS 18.6 simulator. This validates the fallback UI. Native glass validation uses the new manual workflow `LOCAL FRAMES — Liquid Glass Development` (`b5b2a923-f100-49b0-9146-75def1f7df6d`), Xcode 27.2 (27B52), one iPhone 17 Pro Max / iOS 27.2 simulator, required analyze/test actions and an internal-only archive. The existing `com.agilejurf.localframes` identity, team `35TTQQ785M` and App Store Connect app are retained.

Compute usage is recorded only in the private local validation report. The workflow is manual to avoid builds on minor commits. No upgrade or extra compute is authorized. Cloud results, final screenshots and device acceptance must be added after execution; configuration alone is not a passing build.

Local validation executed 36 unit tests (31 passed, 5 model-fixture skips) and all 5 UI tests passed. Cloud Build 45 compiled the native glass implementation and passed Analyze and Archive; one of the 5 UI tests failed because XCTest tapped a style control underneath the floating Generate button. The UI scrolling helper now verifies the target's visible bounds. All 5 local UI tests passed again with that correction. Cloud distribution remains gated on the corrected suite passing there. Simulator tests use normal signing because migration removes a specifically scoped obsolete keychain credential.

The optional grouped-attention conversion experiment in `tools/neodragon/` does not change this app's model manifest or inference implementation. Component parity and Mac process measurements are insufficient to make it a device-validated replacement.

Unit coverage includes original scheduler/numerical guards, cancellation, thermal waits, verified downloads, migration preservation/interruption/symlink handling, export collisions/deleted copies, style persistence and bounded job logging. UI coverage includes all four tabs, keyboard dismissal, expanded prompt editing, style search/custom save, appearance, export placement, Frame Lab and cleanup status. Test fixtures never act as a production generation engine.

## Device acceptance checklist

1. Install the internal build over Build 44 without uninstalling. Confirm existing videos/metadata and the Neodragon installation remain present.
2. In Settings → Storage, capture the measured retired-file bytes and verify the report stays unchanged after another launch.
3. With the installed model, enable Airplane Mode. Generate a two-second Default video using seed 42 and the recorded baseline prompt; export its MP4 and journal.
4. Check playback, Photos export, Files/Videos and Files/Benchmarks; move an export and confirm the private original still works.
5. Check actual Liquid Glass in light/dark modes, keyboard dismissal, Dynamic Type, VoiceOver, Reduce Motion and Reduce Transparency.
6. Test prompt-style selection, custom create/edit/duplicate/delete, favorites, recent styles and saved metadata. Compare styles visually without claiming a trained adapter.
7. Test cancellation and thermal/background pause/resume. A terminated Neodragon process does not yet support disk checkpoint recovery.
8. Treat five-second generation as an open memory-pressure case. Capture the exact journal from each trial. Do not infer longer-duration reliability from the two-second baseline.

Physical-device memory, thermal behavior, battery impact, visual quality and UI overhead have not yet been measured for this redesign. No speed or quality improvement is claimed. The source checkpoint and Build 44 remain the rollback until validation completes. Production merge requires the user's approval.

# Optional Neodragon engine and longer video

Implementation/validation record, 21 November 2026. **Experimental; physical iPhone validation is pending.** Build 38 and the original MOVD package remain the working rollback. This document does not establish an iPhone speed or quality improvement.

## Scope and duration

Neodragon is a separate, optional local text-to-video engine. It uses the published hybrid checkpoint: SSD-1B generates a first image, the video VAE encodes it, and an 18-block Pyramid MMDiT generates genuine subsequent motion latents. A causal video decoder produces the frames. “Hybrid” refers to those local model stages; it does not use a remote inference service, still-image camera effects, repeated frames, or prerecorded footage.

The implementation supports native 512 × 320, 16:10 video at 24 FPS. The new duration selector follows the installed model package's declared, tested tensor range. The candidate longer-duration export covers 2–9 seconds. Two seconds requires 7 latent frames and decodes 49 frames, keeping the first 48. Nine seconds requires 28 latent frames and decodes 217 frames, keeping the first 216. Dropping that one extra causal frame produces the requested duration without slowing playback or looping frames.

MOVD retains its 2–5 second control. Its current fixed Core ML graph produces at most 68 native frames, insufficient for nine seconds at 12 FPS. Increasing a UI constant would not make that model generate the missing frames. Nine-second support therefore belongs to the optional compatible engine. Longer-shape conversion checks do **not** establish long-video quality or physical-device reliability.

## Provenance

| Item | Pinned value |
| --- | --- |
| Source | [Qualcomm-AI-research/neodragon](https://github.com/Qualcomm-AI-research/neodragon), `d2abbe99f46577c4e1db682ad3c26832ec0c23b9` |
| Weights | [Qualcomm-AI-Research/Neodragon](https://huggingface.co/Qualcomm-AI-Research/Neodragon), `5bdc87a4895a4fd148ca14c03181345d278d1040` |
| Downloaded development inputs | 40 selected files, 12,070,716,392 bytes; sizes and SHA-256 pinned in `tools/neodragon/source-lock.json` |
| Native output | 512 × 320 at 24 FPS; optional upstream super-resolution is not included |
| First-image sampler | Original SSD-1B four-step LCM schedule: 999, 749, 499, 249; guidance 0 |
| Motion sampler | Original distilled three-stage flow schedule, one evaluation per stage; timesteps 1000, 744, 386; guidance 0 |
| Evaluations | 4 image evaluations plus 3 for each subsequent latent unit: 22 for two seconds; 85 for nine seconds |
| Randomness | SplitMix64/Box–Muller native stream, fixed seed supported. Reproducible within this port; not PyTorch seed-equivalent |
| Precision | Mixed FP16/FP32, Float32 distilled T5; no INT8 quantization |

The four CLIP encoders and distilled T5 belong to this checkpoint. MOVD's T5 is not substituted. All four CLIP tokenizers enforce their 77-slot limits, including special tokens; T5 enforces 128 slots. Prompts and styles are checked before expensive inference and are never silently truncated. Default style does not append the upstream demonstration's hidden cinematic prompt suffix.

## Conversion and numerical evidence

Checks run on the Intel Mac using Core ML CPU execution, not the target phone. Conversion used Python 3.12, PyTorch 2.2.2, Core ML Tools 8.3, diffusers 0.34.0 and transformers 4.46.3. Exact installed dependencies are recorded in the conversion lock file. Concurrent work and host thermal limits make these runs unsuitable for speed comparisons.

The common component gate requires matching shapes, finite output and relative L2 error at most 0.01 against the pinned original. Arithmetic rewrites are separately checked in PyTorch at at most 1e-5. These gates validate numerical conversion on selected inputs; they do not quantify perceptual video quality.

| Check | Observed result |
| --- | --- |
| Distilled T5, full FP16 | Rejected: all-zero output, relative L2 1 |
| Distilled T5, Float32 | Passed three fixed prompts; retained as the candidate |
| Context adapter, FP16 | Passed three fixed prompt embeddings |
| Four partitioned CLIP encoders | All passed complete chained comparisons, including pooling/penultimate outputs |
| SSD-1B UNet, 77 partitions | Complete chained prediction passed: relative L2 0.000336237 |
| SSD-1B image VAE, 22 partitions | Complete chained decode passed: relative L2 0.001092353 |
| Single-frame video VAE encoder | Exact causal T=1 2D specialization checked against original 3D operations; Core ML relative L2 at most 0.000393 on tested inputs |
| Original 3D image-encoder candidate | Stopped during a long Mac CPU execution; not classified as an unsupported iPhone operation |
| Motion blocks, two-second range | All 18 passed individual reference checks |
| Complete two-second motion prediction | All 18 chained with original geometry and real prompt embeddings; relative L2 0.001110414 |
| Four-stage causal video decoder | Passed original PyTorch versus Core ML comparison |
| Native decoder, 49 and 217 frames | Swift output exactly matched the independent Core ML reference on synthetic latents, maximum relative L2 0 |
| CLIP tokenization | 60 original-vocabulary cases and four overflow checks passed |
| T5 tokenization | Native SentencePiece implementation passed 131 slow-T5 reference cases and overflow rejection |
| Image bridge | Five complete 1024 × 640 resize patterns and 265 rounding cases exactly matched the pinned Pillow preprocessing |
| Native helper/regression tests | Seven tests passed, including tokenizer, tensor strides, schedulers, model isolation and duration reuse |
| Complete native text-to-video | Native macOS CPU Release run executed all 168 partitions and produced a genuine two-second MP4: 48 distinct decoded frames, 512 × 320, 24 FPS. The final buffer-count check was corrected and the same file independently revalidated; see below |
| Nine-second attention exports/full chain | All 18 individual blocks and complete chained prediction passed; full-chain relative L2 0.001275133. No nine-second video success reported |
| Physical iPhone 17 Pro Max | Pending; no speed, memory, quality or reliability improvement claimed |

The first generic Swift T5 integration crashed because its tokenizer dependency does not implement the checkpoint's `Strip` normalizer. The corrected implementation reads the exact original SentencePiece normalization trie and unigram vocabulary. It was compared with the original slow tokenizer, including decomposed Unicode, emoji, special tokens, whitespace and unknown characters. MOVD's tokenizer is unchanged.

The first complete native candidate compiled all 168 models, then stopped at the first SSD-1B CLIP encoder's initial four-layer partition. Its Mac Core ML parity check had passed. The source package, original compiled file and copied test weights have identical SHA-256 values, ruling out a changed weight payload in that copy. The native output is being diagnosed separately; neither a working video nor an iPhone-compatible replacement is inferred from the Mac checks. Numerical reports are preserved in `docs/benchmarks/neodragon-conversion-2026-11-21`.

Native follow-up isolated this first failure to model execution: embeddings matched the original exactly, while direct Core ML transfer, shaped-array transfer and original reference inputs all failed in the same group. Four precision variants were then compared on three original prompts. Float32 passed the iOS 18.4 Intel Simulator check (maximum relative L2 1.924e-7); selective FP16 linear operations and both finite-mask candidates failed with non-finite values. The complete first SSD-1B CLIP encoder was re-exported in Float32 and passed its Mac chained reference check. A simulator retry passed that encoder, then failed at the second mixed-precision encoder's first group.

The exact original mixed-precision group and original inputs also passed a native **macOS** Swift Core ML check on all three prompts (maximum relative L2 0.001155660). This identifies an observed runtime-specific difference; it is not evidence that the iPhone GPU will pass or fail. The Float32 export remains a separate diagnostic alternative. A portable command-line harness now runs the complete, unchanged mixed-precision candidate through the shared Swift engine on macOS CPU. Its environment is explicitly recorded as `macos-cpu`, and its video and measurements cannot be reported as physical iPhone validation. The complete macOS functional run and sampled-frame inspection subsequently passed; physical-device acceptance remains required.

The selected nine-second-range candidate comprises **168 Core ML partitions / 9,965,959,802 bytes** before archive compression. Its eight locally prepared archives total **7,881,071,452 bytes**, with a conservative **32,212,254,720-byte (30 GiB)** installation free-space requirement. Every archive passed decompression/CRC, manifest-entry and SHA-256 checks. These are package byte counts, not measured installed storage or process memory; complete-generation output inspection passed before publication.

Packaging preserves explicit directories, including the empty weights directory referenced by the weightless VAE scale model. A file-only development copy initially failed Core ML compilation at that model; the packaging checks now reject a ZIP missing any model manifest entry. No changed model weights were needed for this fix.

The first complete macOS Debug attempt reached the image VAE's expected `[1, 256, 640, 1024]` activation after all four image diffusion evaluations. Core ML completed that prediction, but the app's generic 100-million-element guard rejected its 167,772,160 elements. The corrected guard is bounded to that exact largest checkpoint activation, checks integer overflow and logical strides, and still rejects larger or invalid shapes. The Release retry passed this stage and the image-conditioning bridge. This was an app tensor-validation failure, not evidence of an unsupported Core ML operation. The failed Debug run took 1,194.712 seconds on this Intel Mac; it is preserved as a failure record and must not be compared with Release timing as an inference optimization.

After this correction, local regression testing executed 86 tests: 80 passed, six skipped, none failed. Five skipped tests require model/reference fixtures, and one requires a separately authorized live upload. Fixture runs and model numerical checks are reported separately from this regression count.

## App behavior and isolation

Setup adds an explicitly optional model card, size/free-space information, download confirmation, pause/resume and independent removal. Create adds model selection, native-format information and a model-specific duration menu. The redundant “While the app is minimized” Setup section is removed. Native Neodragon output does not use Hugging Face smoothing; the existing MOVD smoothing workflow is preserved.

Optional weights live under `Application Support/LocalFrames/OptionalModels/Neodragon`, separate from MOVD's `Models` directory. Downloads use resumable URLSession transfers over Wi-Fi. Every complete archive must match its expected size and SHA-256 before extraction and compilation. Staging is activated only when required runtime models/support files are present. Replacement retains the existing activation rollback; removal affects only the optional model root. No automatic large model download occurs.

Only four small causal decoder models are retained during one job. All other components use the one-partition-at-a-time policy. MOVD's default model retention remains unchanged. Thermal pauses retain an active job in memory; experimental Neodragon jobs do not yet have saved recovery after force quit or process termination. Existing MOVD baseline recovery is preserved.

Progress includes phase estimates derived from the running job's timings, excluding cooling waits. Motion estimates can grow as the attention history grows; unknown decoder costs are not presented as a known full-job finish time. Local diagnostic journals record the correct model revision, expected partitions/evaluations, loads, predictions, memory samples, errors and thermal states. The current optional diagnostics upload schema remains MOVD-specific; Neodragon evidence stays local.

Library records include the optional model ID, revision, native framing, seed, prompt, effective style prompt, resolution and frame rate. Existing videos remain readable, exportable and separately stored. Trained style adapters, image import/conditioning, continuation, upscaling and new remote-generation services are not part of this port.

## Distribution and licenses

Public model files may be distributed as bounded GitHub release assets. [GitHub's release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) allows up to 1,000 assets per release, each under 2 GiB, with no overall release size/bandwidth limit stated. The packager uses a stricter 2,000,000,000-byte asset limit, verifies ZIP contents and SHA-256, and prepares a versioned manifest. It does not itself publish or activate an unverified download. Vercel, the existing backend and its storage are unchanged; no paid hosting or GPU service is provisioned.

The model card specifies BSD-3-Clause-Clear plus [Qualcomm's Responsible AI License](https://www.qualcomm.com/site/responsible-ai-license). Included component notices cover Pyramid Flow, the tiny causal decoder, distilled T5, CLIP, SSD-1B/diffusers, Pillow and SentencePiece references. See `tools/neodragon/THIRD-PARTY-NOTICES.txt`; the same notices are bundled for offline viewing and included with the optional model. This is not an unrestricted-license claim or a patent grant.

## Complete native Mac generation

A Release build of the shared Swift engine completed all 22 diffusion evaluations and video decoding with CPU-only execution requested. All **168 partitions** recorded successful predictions. The actual export contains **48 distinct decoded frames**, **512 × 320**, **24 FPS**, exactly **2 seconds**. SHA-256: `f6afc94854b3c0a8b626d4697552ec7ef7132140f2a657d275605ea748a965a8`. Prompt: “A small sailboat glides across a calm lake at sunrise.” Seed: 42, Default style. The video remains local; it is not a release asset.

The initial CLI verdict was a false failure after the engine had completed. Its compressed reader returned 52 buffers containing 48 samples; four buffers contained no video sample. The harness had counted buffers as frames. The corrected harness decodes real image buffers. It and an independent inspector both revalidated the unchanged MP4 as 48 frames. The original failed journal is retained, with a separate hash-bound revalidation record. No inference or encoding change was needed for this correction.

| Mac CPU observation | Measured value |
| --- | --- |
| Total generation wall time | 1,950.508 seconds (32 min 30.5 sec) |
| Summed model loading time | 596.487 seconds |
| Summed prediction time | 1,155.793 seconds |
| Peak sampled process footprint | 3,187,286,016 bytes |
| Process lifetime peak | 3,233,361,920 bytes; includes the full process lifetime |
| Thermal states sampled | Fair; zero recorded pause time |
| GPU / Neural Engine utilization | Not measured; CPU-only execution requested |

These observations are from an Intel Mac with concurrent development work, not a controlled performance comparison and not an iPhone result. The run's raw journal incorrectly labels non-simulator macOS as `physical-device`; its explicit scope, hardware, OS and final metrics identify macOS CPU execution. The logger now has a separate macOS label. Both corrections are documented in `native-macos-generation-2s-v3.json`, which includes per-partition timings, sampled memory, CPU accounting and hashes for the executable, manifest, journal and video.

Inspection of sampled frames showed a recognizable sailboat, a broadly consistent subject and background, and gradual changes in its position and reflection. This is one qualitative observation, not a visual-quality score or a claim of improvement over MOVD. Frame uniqueness alone does not establish smooth or coherent motion. No full nine-second video has yet been validated.

## Release acceptance still required

The native two-second functional run, export inspection and long-duration component/full-chain checks have passed. On the iPhone, begin with a fixed-prompt two-second Airplane Mode test, retain its video and journal, then attempt longer durations through nine seconds. Record memory, thermals, load/inference time and any failure for each. Do not promote a quality/speed preset or replace MOVD until matched physical-device runs support it.

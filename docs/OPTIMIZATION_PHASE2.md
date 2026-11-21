# Offline optimization: experiment and promotion protocol

The reference source is preserved at `baseline/testflight-build-18` (`2c2d2c745439b79996c51a2c28c8757db82409dd`). Original model archives, their pinned SHA-256 values, T5 weights/tokenizer, model boundaries, local library and exports are retained. New device-derived reports and videos stay in ignored `build/PrivateDeviceReports/`. The optional backend work is separate and unchanged by this phase.

## Current engine

The engine implements rectified-flow Euler updates on a transformed 30-point schedule. It performs 21 transformer evaluations, with a final leap from index 20 to time zero. TDTM is used for the first ten evaluations. Classifier-free guidance uses scale 7 and a batch containing both conditional and unconditional branches. The complete latent has 20 frames regardless of requested output duration. Temporal decoding produces 68 frames; spatial decoding and encoding keep the requested prefix at 256 × 256 and 12 FPS. The supported 2–5-second range is unchanged.

The original STDiT and VAE use Float32 compute. T5 retains its original weight compression. All nine spatial decoder partitions use CPU; other partition policies remain unchanged. Compiled `.mlmodelc` packages are already reused from disk. An `MLModel` instance is loaded and released per partition invocation to limit resident memory. Keeping the whole transformer resident is not assumed feasible.

## Baseline collection

Use **Setup → Benchmark results and comparisons** to inspect local journals and compare saved outputs. The screen shows model/configuration, precision, sampler, diffusion progress, elapsed session time, model loading/prediction totals, peak sampled footprint, thermal states, memory warnings, failures and unfinished operations. It reads locally and does not upload reports.

The three fixed prompts are Sailboat, Flag and Rolling ball. Begin with seed 42 and three fresh full runs per prompt. Expand to seeds 123 and 2026 after establishing repeatability. Keep duration at 2 seconds. Record build/source, model hashes, OS/device, charging state, Low Power Mode, initial thermal state, first-versus-repeat launch and network conditions. Cool to nominal before matched comparisons and alternate candidate/reference run order. Do not discard failures from the result set.

Keep every journal segment, library metadata and MP4. A successful resume demonstrates completion of remaining work, but its elapsed time is not a full-generation baseline. The reader labels resumes and reports restored versus newly completed evaluations. It preserves incomplete/failed outcomes. Missing model predictions are not treated as zero-time operations.

Journal sampling occurs every 250 ms and at operation boundaries; peaks between samples can be missed. New video metrics incorporate the journal's sampled peak as well as runner checkpoints. Earlier library records remain readable but may contain only checkpoint-based memory peaks. Use the detailed journal for comparisons. GPU/Neural Engine utilization still requires a compatible physical-device profiler; simulator tests and compute-plan preferences do not provide it.

## Precision screening

`scripts/probe_precision_candidate.py` creates a separate package, refuses to overwrite an existing candidate, verifies that original bytes are unchanged, and rejects changes to input/output names, types, shapes or flexible ranges. It is pinned to coremltools 8.3.0. Float16 screening uses the internal MIL-proto reader, so a production candidate should be reproduced with the pinned upstream PyTorch exporter and checkpoint before promotion.

Three modes are available:

- `fp16`: Float16 operations where supported, with original Float32 input/output contracts.
- `mixed`: Float16 convolution/linear/matmul operations; other operations retain Float32.
- `int8`: per-channel symmetric INT8 weights for convolution/linear/matmul above the threshold; original compute precision is retained.

The numerical screen is declared before evaluation: identical contracts and output shapes, finite output, and relative L2 error at most 0.01 against the original CPU partition on the same synthetic input. Passing is only permission to investigate further. It does not establish PyTorch parity, acceptable full-video quality, device compatibility, runtime memory or acceleration. A candidate failing the screen is not installed in the app.

Example after running the original spatial probe:

```sh
.venv/bin/python scripts/probe_precision_candidate.py \
  --model build/DecoderProbe/Models/vae_spatial_part3_1.mlpackage \
  --output build/PrecisionProbes/vae-spatial-3-1-mixed-new \
  --mode mixed \
  --input build/SpatialDecoderProbe/cpu/vae_spatial_part2.npy \
  --reference build/SpatialDecoderProbe/cpu/vae_spatial_part3_1.npy
```

Each report records package byte counts/hashes, input/output hashes, finite checks, error metrics, software versions and limitations. Mac timings are diagnostic with uncontrolled caches and must not be described as iPhone performance. Run-specific artifacts are excluded from the app and public repository.

Apple documents [typed precision and mixed precision](https://apple.github.io/coremltools/docs-guides/source/typed-execution.html), and [weight/activation quantization](https://apple.github.io/coremltools/docs-guides/source/opt-quantization-api.html). Weight-only INT8 compression does not by itself change Float32 operation precision or prove Neural Engine acceleration. Full Float32 ML Programs cannot run on the Neural Engine. FP16 candidates need fresh compute-plan and runtime checks; do not force the spatial chain onto GPU/ANE solely because a planner accepts it.

## Sampler, guidance and loading experiments

Prioritize the measured prediction/loading breakdown. Evaluate STDiT precision with actual intermediate inputs before changing the sampler. Full-model comparisons must include both ST and TDTM branches, conditioning masks, timestep transforms, guidance and temporal decoding. Preserve Float32 for numerically sensitive reductions, normalization, division, attention and masks as evidence requires.

Reduced-step experiments require a consistent rectified-flow schedule, final endpoint and documented TDTM/leap transition. Truncating the current loop would change the endpoint incorrectly. Test one change at a time and retain fixed prompt/seed outputs. Higher-order rectified-flow methods such as [RF-Solver](https://arxiv.org/abs/2411.04746) are research candidates, not validated drop-in replacements for MOVD's current schedule. Compare function-evaluation count, not only the displayed number of steps.

Changing CFG scale alone does not remove either branch from the current batch-two exported graph. Avoid promising a speed gain without a compatible export and matched quality measurements. Likewise, model-instance caching trades memory for load latency; estimate its achievable benefit from measured load totals before retaining additional partitions. A bounded cache must release on cooling, background loss and memory warning, and pass repeated device runs before becoming default.

## Preset acceptance

Fast, Balanced and Quality are visible as pending configurations, with no arbitrary step count assigned and no selection enabled. Promote a preset only after:

1. All relevant partitions load and execute on the physical target, with finite intermediates and complete, valid MP4 output.
2. The fixed cases pass repeated generation, including a disconnected launch and generation with Airplane Mode and Wi-Fi off.
3. Matched measurements show the intended latency, memory or quality benefit, with failure rate and thermal interruptions retained. Report median/spread; do not claim an improvement from a single faster run.
4. Side-by-side inspection finds no unacceptable subject changes, prompt mismatch, motion collapse, unstable background, flicker or artifacts. Frame metrics supplement visual assessment; lower frame differences can reward a frozen video.
5. The original model, outputs and settings remain available for rollback. No quantized model becomes the default before these device tests.

## Optional enhancement and longer output

[RIFE](https://github.com/hzwer/ECCV2022-RIFE) provides frame interpolation, including a lite variant identified by its authors for diffusion-video postprocessing. [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) provides restoration/upscaling candidates; its compact anime model is not assumed appropriate for general photographic scenes. Verify exact checkpoint licensing, Core ML conversion, intermediate memory, motion artifacts and device thermal behavior before adding either. No enhancement model is installed by this phase.

A 5-second, 24 FPS option would require 120 output frames. Evaluate an optional interpolation stage after genuine 12 FPS generation, saving a new derivative while retaining the original. Test endpoint handling, constant frame rate, duration, motion and occlusion artifacts. Merely writing the existing 60 frames at 24 FPS would halve the duration.

A 10-second generation exceeds the current 68-frame decode and exported transformer shapes. The first transformer stage accepts a flexible latent temporal dimension, but the ST block input permits at most 7,820 tokens. At 256 × 256, 40 latent frames would require 10,240 tokens. The temporal decoder consumes groups of five latent frames, so eight groups would be required to reach at least 120 decoded frames. A flexible first stage alone is insufficient. This needs compatible longer-context exports or validated overlapping generation with temporal conditioning. Independently stitching unrelated clips does not demonstrate continuity. The support backend does not increase the device model's frame capacity.

## Reliability and current build scope

The encoder now has a compatible Core Video buffer-pool fallback if AVFoundation's optional adaptor pool is unavailable. A regression test forces that path, writes an MP4, decodes all 24 frames and checks its two-second duration. This is an export-reliability candidate, not an inference speedup. [Apple's adaptor documentation](https://developer.apple.com/documentation/avfoundation/avassetwriterinputpixelbufferadaptor) describes appending pixel buffers and the efficiency of its provided pool.

The development build contains measurement/comparison UI and the encoder fallback. It retains the original weights, 21 evaluations and current compute policy. Precision prototypes remain local. Physical validation of this new build and matched optimized-generation measurements are required before the optimization deliverables can be considered complete.

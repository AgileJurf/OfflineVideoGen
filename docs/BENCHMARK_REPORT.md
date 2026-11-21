# iPhone 17 Pro Max feasibility and benchmark record

Status: **baseline device execution pending; no performance improvement established**. This is a record of current evidence and the measurement procedure, not a completed device-performance result.

## Observed evidence

| Requested check | Current evidence |
| --- | --- |
| Installable physical-device beta | Xcode Cloud Build 5 archived and distributed successfully; TestFlight 0.1.0 (5) is Testing in the internal group |
| Physical iPhone identification | Paired wired iPhone 17 Pro Max, hardware family iPhone18,2, iOS 27.3 beta; Developer Mode enabled |
| Model download on the phone | Tester confirmed the app is installed and model download is running; completion and compilation are not yet established |
| Genuine 2-second generation | No completed physical-device MP4 or measurement log received yet |
| All 102 required partitions | Inventory known; runtime loading and prediction coverage remain unmeasured on the phone |
| Generation time, memory, thermal state, CPU | No physical-device benchmark values available yet |
| GPU utilization and actual compute placement | Instruments attachment blocked by missing compatible developer disk image |
| Float16 comparison | Export format and conversion path investigated; no converted model or parity result claimed |
| Fewer steps / alternative sampler | No changes or speedup claims; baseline uses 21 model evaluations on a 30-point schedule |
| Visual quality, motion, prompt adherence | Awaiting actual baseline and candidate videos |
| Rollback | Public tag `baseline/testflight-build-5` preserves source `df73d09de302b28e0e6af6ee16ff24211e9cdb35`; original archives and pinned hashes remain unchanged |

The Mac has Xcode 16.4 on macOS 15.8.3 (Intel). CoreDevice reports that its personalized developer image lacks the requested hardware variant. Refreshing Apple's Xcode device-support components did not resolve it. A compatible Xcode/device-support environment is needed for Instruments. TestFlight can install and run the app independently of that debugger connection. Simulator test passes are not iPhone performance measurements.

## Measurement implementation

The benchmark runs the existing MOVD engine with the same models, partition boundaries, CPU/GPU policy, guidance, frame count, and sampler. The ordinary generation path leaves the optional prediction logger disabled. Model setup records download, checksum, extraction, and per-partition compilation events. A completed installation from an earlier build remains valid; its earlier timings cannot be reconstructed.

**Setup → Device benchmark → Run 2-second baseline** uses one of three fixed prompts and an explicit unsigned-integer seed (default 42). It records:

- Separate elapsed times for every model load and prediction, including repeated calls and input shapes.
- A journal entry before each operation and success/error afterward. Logs without a terminal event remain incomplete and are exportable after relaunch; the last started operation is evidence of where execution was interrupted, not proof of its cause.
- Process physical-footprint samples every 250 ms, thermal state, and cumulative process CPU time. CPU time excludes work charged to separate system services and includes instrumentation overhead.
- The OS process-lifetime footprint high-water mark, explicitly distinct from a run-specific peak. Samples can miss spikes between observations. No GPU-utilization value is inferred from CPU time or requested compute units.
- Hardware family, OS, app version/build, source revision, model revision, manifest hash, prompt, seed, and sampler settings.
- For a completed benchmark, the actual MP4 and metadata, SHA-256, duration, dimensions, and frame rate. Container validity is distinct from visual quality.

**Export benchmark files** exports the local journals, completed videos, and metadata. No benchmark telemetry is automatically uploaded. Keep the original files together. The source-revision resource is stamped by Xcode Cloud; local development builds are labeled unversioned until explicitly stamped.

Generate a report from exported evidence:

```sh
python3 scripts/summarize_benchmarks.py /path/to/exported-files --output /path/to/benchmark-report.md
```

The report preserves missing/failed measurements, lists every required partition, verifies exported video hashes, and reports loading versus prediction totals, medians, p95 timings, active process-footprint samples, and errors. Per-partition footprints describe the whole process during that operation. Different input shapes/stages must be separated using the raw logs when making fine-grained comparisons.

## Baseline execution order

1. Finish installation over Wi-Fi, keeping the app open. Record errors verbatim. Do not update an app during active installation or generation.
2. Install the instrumented beta through TestFlight after setup finishes. Updating preserves the app's model sandbox; deleting the app does not.
3. Let the phone cool to nominal thermal state. Record charging state, battery level, Low Power Mode, ambient conditions, other activity, and first-versus-repeat run. These environmental details are not currently captured automatically.
4. Run the sailboat prompt, seed 42, duration 2 seconds. The target is 24 frames at 12 FPS and 256 × 256. Keep the app in the foreground. Preserve failed runs as well as successes.
5. If successful, export the MP4 and journal, inspect real motion and prompt adherence, then repeat with Airplane Mode enabled and Wi-Fi explicitly off. That second run establishes offline operation after installation.
6. Once a genuine baseline succeeds, repeat each of the three prompt/seed cases at least three times under documented comparable conditions. Report every outcome, median/spread, and thermal interruptions; do not average only successful fast runs.
7. Then run **Inspect compute plans**. This inspects all 102 partitions with CPU-only, CPU/GPU, CPU/Neural Engine, and all-compute configurations. It logs compatible/preferred devices and estimated cost. These planner results are not proof of actual execution or speed.
8. With compatible device support, capture Core ML, Neural Engine, GPU/Metal, Time Profiler, and memory Instruments traces aligned with the model-operation signposts. Preserve traces locally; sanitize account and device identifiers before sharing publicly.

Apple documents the distinction between [compute-plan estimates](https://developer.apple.com/documentation/coreml/mlcomputeplan-1w21n) and the [Core ML Instruments template](https://developer.apple.com/documentation/xcode-release-notes/xcode-14-release-notes), which combines Core ML, Neural Engine, GPU, and CPU profiling.

## Float16 investigation

Static inspection of all 103 locally downloaded package specifications found ML Program representations. Top-level operation output declarations include Float32, integer, Boolean, and string values, with no Float16 declarations in that inspection. T5's weight quantization is separate from its operation/output precision. The engine uses 102 packages; the unused combined temporal package is replaced by smaller partitions.

The pinned upstream [STDiT exporter](https://github.com/eai-lab/MOVD/blob/cc1839814d0e1b0cb01953831a55a557ff6682bf/Device_conversion/coreml-export/stdit3/export-stdit3.py), [spatial VAE exporter](https://github.com/eai-lab/MOVD/blob/cc1839814d0e1b0cb01953831a55a557ff6682bf/Device_conversion/coreml-export/vae/export-vae-spatial.py), and [temporal VAE exporter](https://github.com/eai-lab/MOVD/blob/cc1839814d0e1b0cb01953831a55a557ff6682bf/Device_conversion/coreml-export/vae/export-vae-temporal.py) explicitly request Float32 ML Program conversion. Apple supports [Float16 and selective mixed-precision conversion](https://apple.github.io/coremltools/docs-guides/source/typed-execution.html). A Float32 ML Program excludes Neural Engine execution; changing the compute-unit setting alone does not convert its precision.

After a successful baseline, create separately named candidate packages and a separate manifest. Re-export from the pinned trusted source/checkpoint with Float16 compute precision; preserve existing Float32 input/output boundaries initially to avoid changing engine interfaces. Avoid assuming that casting all operations is numerically safe. Inspect normalization, softmax, division, large activations, attention-mask casts, temporal boundary tensors, and dtype changes. Preserve Float32 selectively where parity requires it. Float16 storage arithmetic suggests smaller tensors, but no device memory or latency reduction is claimed before measurements.

Validate captured real intermediate inputs against the baseline for each converted partition: shapes/dtypes, finite values, absolute/relative errors, normalized RMS error, and cosine similarity. Use a separate correctness run for tensor capture to avoid contaminating timing measurements. Compare end-to-end fixed-seed outputs with frame PSNR/SSIM, perceptual metrics where available, temporal consistency, and blinded human review of motion/prompt adherence. Metrics alone do not establish perceptual equivalence. Candidate acceptance thresholds must be specified before judging results.

## Sampler and step investigation

The current native integration uses rectified-flow updates, a 30-point schedule, the upstream LPL leap at index 20, 21 evaluations, TDTM for the first ten iterations, and guidance scale 7. It denoises the full twenty-frame latent sequence for every requested duration, then saves a decoded prefix; choosing 2 seconds does not proportionally reduce diffusion work.

After parity and a completed baseline, vary one factor at a time. First evaluate fewer rectified-flow evaluations while preserving the documented timestep transform and final update. Keep TDTM scheduling and the leap transition explicit; do not equate reducing a loop bound with a valid sampler. An alternative sampler needs a verified derivation for this rectified-flow parameterization and upstream reference comparison. No drop-in DDIM/DPM replacement is currently validated in this app. Reuse prompts/seeds and matched conditions, preserve all videos, and report failure rates and quality regressions alongside timing.

## Next recommendation

**Complete and preserve one genuine 2-second physical-device generation first.** If it fails, use the last journal entry and Core ML error to resolve that concrete failure without changing architecture. Once it succeeds, use measured loading versus prediction cost and memory evidence to select the next experiment. Float16 is a candidate for reducing model/tensor storage and enabling some Neural Engine-compatible work, but it is not yet a measured improvement. No baseline/optimized performance comparison can responsibly be reported at the present evidence level.

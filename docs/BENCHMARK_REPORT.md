# iPhone 17 Pro Max feasibility and benchmark record

Status: **physical installation verified; two baseline attempts interrupted in the first TDTM prediction; no completed video or generation speedup established**. Measurements below come from three exported build 8 journals, received on 21 November 2026 (Pacific). TestFlight build 10 is available for the controlled memory-allowance experiment; its device results are pending.

## Observed evidence

| Requested check | Current evidence |
| --- | --- |
| Installable physical-device beta | TestFlight 0.1.0 (10), source `8d0cd48`, is Testing in the internal group. Cloud Build 9 passed tests and static analysis; Build 10 archived and delivered successfully. Measured baseline build 8 and original build 5 remain available |
| Physical iPhone identification | Paired wired iPhone 17 Pro Max, hardware family iPhone18,2, iOS 27.3 beta; Developer Mode enabled |
| Model installation on the phone | Exported journal confirms all three SHA-256 checks, 102 successful compilations, and terminal installation success. STDiT archive was reused; T5 and VAE were downloaded during this recorded attempt |
| Genuine 2-second generation | 0/2 completed. Both attempts ended during `stdit3_TDTM_0` prediction at step 1; no MP4 or terminal journal event |
| All 102 required partitions | 102 compiled; 28 loaded and 27 completed a prediction in each attempt. First TDTM prediction was interrupted; 74 partitions were not reached for loading/prediction |
| Generation time, memory, thermal state, CPU | Partial-run measurements are available below; full generation time and final peak remain unknown |
| GPU utilization and actual compute placement | Instruments attachment blocked by missing compatible developer disk image |
| Float16 comparison | Export format and conversion path investigated; no converted model or parity result claimed |
| Fewer steps / alternative sampler | No changes or speedup claims; baseline uses 21 model evaluations on a 30-point schedule |
| Visual quality, motion, prompt adherence | Awaiting actual baseline and candidate videos |
| Rollback | Public tags `baseline/testflight-build-5` and `baseline/testflight-build-8` preserve the original source and instrumented failing baseline. Original archives and pinned hashes remain unchanged |

The Mac has Xcode 16.4 on macOS 15.8.3 (Intel). CoreDevice reports that its personalized developer image lacks the requested hardware variant. Refreshing Apple's Xcode device-support components did not resolve it. A compatible Xcode/device-support environment is needed for Instruments. Apple's [current compatibility table](https://developer.apple.com/xcode/system-requirements) lists Xcode 27.3 beta 2 with the matching iOS 27.3 SDK and requires macOS 26.6 or later. TestFlight can install and run the app independently of that debugger connection. Simulator test passes are not iPhone performance measurements.

## Physical-device results from build 8

The logs identify an iPhone18,2 running iOS 27.3 build 24C5037i, app 0.1.0 (8), source `fd113f2c1cbbd724247406c587fe1826fac90a68`. Both generation attempts use the sailboat prompt, seed 42, 256 × 256, 12 FPS, and a requested duration of 2 seconds. The model revision and manifest hash match the repository, and all event sequences are contiguous. The first attempt follows installation in the same process; the second follows relaunch. OS caches and environmental conditions were not controlled. These two failed attempts are not an optimization comparison.

| Recorded metric | Attempt A (00:10:22 PST) | Attempt B (00:11:02 PST) |
| --- | ---: | ---: |
| Last recorded elapsed time, not generation completion time | 14.255 s | 9.008 s |
| Completed model loads | 28 | 28 |
| Completed partition predictions | 27 | 27 |
| Sum of completed load times | 8.751 s | 4.134 s |
| Sum of completed prediction times | 4.671 s | 3.936 s |
| App CPU-time increase over recorded interval | 7.161 s | 4.313 s |
| Mean app CPU use, relative to one core | 50.2% | 47.9% |
| Highest recorded process footprint | 3,383,038,384 bytes | 3,186,020,544 bytes |
| Memory-warning footprint | 2,840,186,904 bytes | 2,855,227,320 bytes |
| Thermal state throughout recorded interval | nominal | nominal |
| Last unfinished operation | `stdit3_TDTM_0 / predict` | `stdit3_TDTM_0 / predict` |

The TDTM model loaded successfully in 0.394 and 0.491 seconds. Its first prediction began with approximately 1.20 and 1.17 GB of app footprint, then memory rose above 3 GB before logging stopped. Input shapes were `x:[2,5120,1152]`, `y:[1,30,1152]`, `attn:[1,16,5120,30]`, `t_mlp:[2,6912]`, and `T:[1]`. All 26 T5 predictions and `stdit3_part1` completed. The largest completed load cost was T5 layer 0 in attempt A; the immediate feasibility blocker is the first TDTM prediction's memory growth. No VAE execution or completed diffusion step has been established.

The OS lifetime footprint high-water marks equal the largest recorded footprints in these two journals, but logging ends before the final termination. They remain lower bounds on the full attempt's peak. CPU time excludes separate Core ML service processes. GPU utilization, actual CPU/GPU placement, Neural Engine activity, and final termination reason are not measured by these files. Memory warnings followed by termination support a memory-pressure hypothesis; a [Jetsam event report](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports) is needed to distinguish a per-process limit from other OS termination reasons. TestFlight Crash Feedback currently has no report, and direct device crash-log access is blocked by the same developer-image incompatibility.

Resumed installation completed in 236.257 seconds, with 110,200,552 bytes maximum recorded app footprint and 111,101,672 bytes process-lifetime high-water mark. STDiT verification took 3.654 seconds and extraction 37.363 seconds. T5 download/verification/extraction took 153.989/1.951/21.713 seconds; VAE took 10.997/0.194/2.548 seconds. The sum of 102 compilation-call durations was 3.264 seconds. These figures exclude the prior STDiT download and memory charged to separate compiler services. They do not constitute a timing comparison against build 5.

The [detailed per-partition report](BUILD8_DEVICE_EVIDENCE.md) lists all 102 partitions for each journal, including missing execution measurements. The [evidence index](BUILD8_EVIDENCE_INDEX.json) records input-log SHA-256 hashes. Raw journals remain local. Reproduce the derived report using `scripts/summarize_benchmarks.py` with the three original exported files.

## Next controlled feasibility experiment

Build 8 does not request Apple's [Increased Memory Limit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit). TestFlight build 10 requests it and adds [available app-memory samples](https://developer.apple.com/documentation/os/os_proc_available_memory) so the device's actual allowance can be observed. This is advisory and device-dependent; the phone's physical RAM does not equal an app's allocation limit. It is not a memory-use reduction, confirmed fix, or speed improvement.

Build 10 is available to the existing internal tester from source `8d0cd48164cad3a135f00bb562394c73623e7cdf`. Its 11 unit and 2 UI tests passed locally, 4 report-parser tests passed, and Cloud Build 9 passed Test and Analyze. Cloud Build 10 archived and delivered successfully. Inspection of the downloaded App Store export found the entitlement set to true in its XML and DER signature payloads and provisioning profile. Both entitlement payload hashes match the CodeDirectory. The older local `codesign` could not decode this export; this independent payload/hash inspection is not a full CMS signature validation or proof of a runtime memory grant. [Package hashes and inspection details](BUILD10_PACKAGE_VERIFICATION.json) preserve those limits explicitly.

This candidate preserves model weights, precision, tensor shapes, sampler, guidance, compute-unit requests, and memory/thermal cancellation checks. Repeat the same sailboat/seed-42 run and export its journal. Success requires a genuine 2-second MP4 and successful partition coverage. If the same prediction still fails or no extra allowance is available, use that evidence to test a separate CPU-only placement for the failing partition or a validated, separately stored Float16 conversion. Do not combine those changes with this first experiment. The build 8 tag and TestFlight binary remain the comparison and rollback point.

## Reproduced installation blocker

The checksum loop used 1 MiB `FileHandle` reads, but Foundation's autoreleased read buffers survived the synchronous loop. A standalone optimized Swift probe reproduced growing memory on the Intel Mac. Wrapping each read and hash update in an `autoreleasepool` bounds buffer lifetime without changing the bytes hashed or skipping integrity verification.

Three fresh-process pairs hashed the same 256 MiB sparse zero-filled fixture. The measured metric was `task_vm_info.ledger_phys_footprint_peak`, the OS process-lifetime footprint high-water mark, not a heap-allocation counter:

| Run | Original peak bytes | Fixed peak bytes | SHA-256 equality |
| --- | ---: | ---: | --- |
| 1 | 269,336,576 | 1,884,160 | Identical |
| 2 | 269,299,712 | 1,871,872 | Identical |
| 3 | 269,291,520 | 1,875,968 | Identical |

The fixed probe also completed the actual 8,896,191,116-byte STDiT archive: 181.397 seconds, 2,023,424 bytes process-lifetime peak footprint, and the expected SHA-256 `7430806d03d94bed32fbff7a9d0c27d36af073dff6f9da4f31cfd3785bff391c`. The original loop was not run against the full archive. These are standalone Mac checksum measurements, not the iPhone app's total memory or video-generation performance. Disk/cache conditions were not controlled for a latency comparison. Raw sanitized results are in [CHECKSUM_MEMORY_RESULTS.json](CHECKSUM_MEMORY_RESULTS.json).

Reproduce the paired fixture measurement on macOS:

```sh
swiftc -O scripts/benchmark_checksum_memory.swift -o /tmp/localframes-checksum-probe
mkfile -n 256m /tmp/localframes-checksum-fixture.bin
for run in 1 2 3; do
  /tmp/localframes-checksum-probe baseline /tmp/localframes-checksum-fixture.bin
  /tmp/localframes-checksum-probe bounded /tmp/localframes-checksum-fixture.bin
done
```

The app fix also separates verification, extraction, and named-partition compilation in progress messages, throttles download UI updates, records memory warnings in the diagnostic journal, and replaces the blanket generation alert with stage-aware handling. Bounded download/checksum work continues after a warning; extraction, compilation, and generation retain cancellation protection. Completed downloaded archives remain available for verification on retry. Compilation itself restarts on a retry. No weights, partition boundaries, model precision, or diffusion steps were changed. The simulator regression test hashes a 64 MiB file inside an outer autorelease pool and checks both the expected digest and bounded footprint growth; all 11 unit and 2 UI tests passed locally.

The fix and diagnostic capture are available in TestFlight 0.1.0 (8). The later exported installation journal confirms that the original installation blocker was passed and all 102 partitions were prepared. Genuine generation remains blocked by the first TDTM prediction described above. There is no matched build 5 device log from which to calculate a device-memory or latency improvement.

## Measurement implementation

The benchmark runs the existing MOVD engine with the same models, partition boundaries, CPU/GPU policy, guidance, frame count, and sampler. The ordinary generation path leaves the optional prediction logger disabled. Model setup records download, checksum, extraction, and per-partition compilation events. A completed installation from an earlier build remains valid; its earlier timings cannot be reconstructed.

**Setup → Device benchmark → Run 2-second baseline** uses one of three fixed prompts and an explicit unsigned-integer seed (default 42). It records:

- Separate elapsed times for every model load and prediction, including repeated calls and input shapes.
- A journal entry before each operation and success/error afterward. Logs without a terminal event remain incomplete and are exportable after relaunch; the last started operation is evidence of where execution was interrupted, not proof of its cause.
- Process physical-footprint samples every 250 ms, thermal state, and cumulative process CPU time. CPU time excludes work charged to separate system services and includes instrumentation overhead.
- The OS process-lifetime footprint high-water mark, explicitly distinct from a run-specific peak. Samples can miss spikes between observations. No GPU-utilization value is inferred from CPU time or requested compute units.
- The memory-limit candidate additionally records `os_proc_available_memory` on physical iOS devices. This field is absent in build 8 and simulator logs; missing values are not zero.
- Hardware family, OS, app version/build, source revision, model revision, manifest hash, prompt, seed, and sampler settings.
- For a completed benchmark, the actual MP4 and metadata, SHA-256, duration, dimensions, and frame rate. Container validity is distinct from visual quality.

**Export benchmark files** exports the local journals, completed videos, and metadata. No benchmark telemetry is automatically uploaded. Keep the original files together. The source-revision resource is stamped by Xcode Cloud; local development builds are labeled unversioned until explicitly stamped.

Generate a report from exported evidence:

```sh
python3 scripts/summarize_benchmarks.py /path/to/exported-files --output /path/to/benchmark-report.md
```

The report preserves missing/failed measurements, lists every required partition, verifies exported video hashes, and reports loading versus prediction totals, medians, p95 timings, active process-footprint samples, and errors. Per-partition footprints describe the whole process during that operation. Different input shapes/stages must be separated using the raw logs when making fine-grained comparisons.

## Baseline execution order

1. Keep the installed model and build 8 evidence. Update to 0.1.0 (10) through TestFlight with no generation in progress. Deleting the app removes its model and logs.
2. Installation is now verified on the target phone and need not be repeated for an app update. Preserve the successful installation journal and failed generation attempts.
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

**Test the requested memory allowance against the reproducible first-TDTM memory interruption, then complete and preserve one genuine 2-second physical-device generation.** Keep the failed build 8 baseline and change one factor at a time. Float16 remains a candidate for reducing model/tensor storage and enabling some Neural Engine-compatible work, but it is not yet a measured improvement. No baseline/optimized inference-performance comparison can responsibly be reported without a completed candidate and comparable evidence.

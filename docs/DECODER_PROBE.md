# Decoder partition probe

The current `spatial-cpu-v2` candidate requests CPU-only execution for all nine spatial VAE partitions. It preserves the model files and diffusion schedule. Physical completion and output quality must still be validated; requesting a compute unit does not establish a device speed improvement. The earlier `spatial-attention-cpu-v1` policy is retained at `baseline/testflight-build-16` for comparison.

`scripts/probe_decoder_partition.py` runs the real `vae_spatial_part2` partition, whose original Float32 specification contains a single 512-wide scaled-dot-product-attention head, on deterministic synthetic inputs in an existing macOS coremltools/NumPy environment. Extract the original package from the verified VAE archive without altering it. Run each policy in a fresh process so a native runtime abort cannot terminate the other probe:

```sh
.venv/bin/python scripts/probe_decoder_partition.py \
  build/DecoderProbe/Models/vae_spatial_part2.mlpackage \
  --compute cpu --output build/DecoderProbe/cpu
.venv/bin/python scripts/probe_decoder_partition.py \
  build/DecoderProbe/Models/vae_spatial_part2.mlpackage \
  --compute cpu-gpu --output build/DecoderProbe/cpu-gpu
```

Use new output directories for repeats. The JSONL records the environment, input hashes, load/prediction times, output shape/type, finite status, range and output hashes. Arrays are saved locally for numerical comparisons. This is a Mac synthetic partition test, not an iPhone benchmark, video-generation result or PyTorch parity test. Check numerical agreement before treating a faster result as valid. Keep real-device journals and private measurement reports outside the public repository.

The app logs decoder policy separately from the diffusion checkpoint format. A completed build-14 checkpoint remains compatible and resumes directly at decoding. Timing history includes the policy and is relearned after a change. See [continuation and recovery](RESUMABLE_BASELINE.md).

## Complete spatial chain

The `spatial-cpu-v2` candidate requests CPU-only execution for all nine spatial partitions. Extract all nine original packages from the verified VAE archive into the model directory. The full-chain probe uses a seeded synthetic Float32 `[1,4,4,32,32]` input and feeds each CPU output into the next original partition. It must finish with finite `[1,3,4,256,256]` output. Each prediction runs in a separate process; its journal survives a native abort.

```sh
.venv/bin/python scripts/probe_spatial_decoder.py \
  --models build/DecoderProbe/Models --policy cpu \
  --output build/SpatialDecoderProbe/cpu
.venv/bin/python scripts/probe_spatial_decoder.py \
  --models build/DecoderProbe/Models --policy build16 \
  --reference build/SpatialDecoderProbe/cpu \
  --output build/SpatialDecoderProbe/build16
```

The second command compares every partition against the CPU run using identical saved boundary inputs, allowing later partitions to be inspected even after an earlier failure. CPU output is a comparison reference, not an independent PyTorch ground truth. Each worker records input/output hashes, shapes, dtype, numerical range, finite status, nonzero count, timing and process-lifetime maximum RSS. RSS is local Mac process accounting, not iPhone physical-footprint telemetry. Numerical comparisons use Float64 reductions. Use fresh directories for repeats and compare hashes; these synthetic arrays are never substituted for generated video.

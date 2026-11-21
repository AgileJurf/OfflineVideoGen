# Decoder partition probe

The compatibility policy `spatial-attention-cpu-v1` requests CPU-only execution for `vae_spatial_part2`. Its original Float32 specification contains a single 512-wide scaled-dot-product-attention head. This leaves the model files and diffusion schedule unchanged. Physical completion and output quality must still be validated; requesting a compute unit does not establish a device speed improvement.

`scripts/probe_decoder_partition.py` runs that real partition on deterministic synthetic inputs in an existing macOS coremltools/NumPy environment. Extract the original package from the verified VAE archive without altering it. Run each policy in a fresh process so a native runtime abort cannot terminate the other probe:

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

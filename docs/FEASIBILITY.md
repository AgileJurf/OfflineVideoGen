# Feasibility record

Research date: 20 November 2026. Target: a standalone native iPhone app producing 2–5 second videos offline at 256–384 pixels and 8–12 FPS.

## Decision

Use the publicly released **MOVD / Open-Sora Core ML partitions** for an experimental integration. They provide an actual temporal diffusion transformer and video VAE, plus a native Swift reference. This is the most concrete released iOS path found, but it is not evidence that this new app can run successfully on iPhone 17 Pro Max.

The upstream [MOVD repository](https://github.com/eai-lab/MOVD) is pinned to `cc1839814d0e1b0cb01953831a55a557ff6682bf`. The [WACV 2026 paper](https://openaccess.thecvf.com/content/WACV2026/papers/Kim_Mobile-Oriented_Video_Diffusion_Enabling_Text-to-Video_Generation_on_Mobile_Devices_Without_WACV_2026_paper.pdf), Table 5, reports 416.50 seconds at 192 × 192 and 638.09 seconds at 256 × 256 on iPhone 15 Pro. Those are the authors' measurements, not measurements of this app or an iPhone 17. They suggest minutes of latency, not interactive generation.

## Candidates checked

| Candidate | Released path found | Assessment for this app |
| --- | --- | --- |
| [MOVD](https://github.com/eai-lab/MOVD) | Swift implementation, exporters, partitioned Core ML downloads | Selected experimental path; substantial storage and CPU/GPU work. |
| [SnapGen-V](https://snap-research.github.io/snapgen-v/) | Paper, demos, reported mobile benchmarks | No public model weights or complete downloadable iOS inference release found on the official project page. |
| [S2DiT](https://snap-research.github.io/S2DiT/) | Paper and demonstrations | No usable released Core ML checkpoint found on the official project page. |
| [MobileVD](https://qualcomm-ai-research.github.io/mobile-video-diffusion/) | Image-to-video research; code/checkpoint links marked forthcoming | Not a released native text-to-video solution. |
| [MobileWan](https://github.com/Qualcomm-AI-research/MobileWan) | Python implementation and released mobile-optimized transformer | Not a ready iOS pipeline; the optimized mobile decoder is not released. Requires conversion and memory validation. |
| [MobileI2V](https://github.com/hustvl/MobileI2V) | Image-to-video checkpoint and Python code | Not direct text-to-video; no ready Core ML pipeline found. |

Absence of a release here means none was found in the reviewed official sources on the research date, not a claim that publication cannot happen later.

## Concrete model inventory

The app's bundled manifest records locally measured hashes for the archives linked by MOVD. These are reproducibility pins, not publisher-signed checksums.

| Archive | Bytes | SHA-256 |
| --- | ---: | --- |
| STDiT-TDTM.zip | 8,896,191,116 | `7430806d03d94bed32fbff7a9d0c27d36af073dff6f9da4f31cfd3785bff391c` |
| T5.zip | 4,806,701,041 | `f7469e5904b5de7e02b590c8d56f8312b2b6555529f0c69ef3afb6665132b8a2` |
| VAE.zip | 430,944,457 | `067afcf6e45e1fb39e12e1be5f266c63383ce198d524549deace450ee8022e2c` |

The archives contain 103 packages; this engine uses 102. The unused combined `vae_temporal_part2_3` package is replaced by the four released smaller partitions. The T5 exporter uses int8 weight quantization; STDiT and VAE exports use float32. Disk size is not runtime memory use. Actual installed size and process peak remain unmeasured.

## Native engine choices

- 256 × 256 output, 12 FPS, 24/36/48/60 frames for 2/3/4/5 seconds.
- Twenty latent frames; temporal VAE produces 68 generated frames. The encoder keeps the requested prefix without repeating frames, interpolating still images, or substituting sample media.
- Thirty-point rectified-flow schedule with the upstream LPL leap at index 20, ten early TDTM iterations, and guidance scale 7.
- Local T5 tokenizer and text encoder. Prompts are limited to 500 characters and 63 tokenizer tokens to bound attention-mask memory.
- Core ML CPU/GPU on a device and CPU in the simulator. Some VAE partitions use CPU only, following the reference. Neural Engine execution is not claimed.
- Individual partition loading, streamed spatial decoding to AVAssetWriter, cancellation checkpoints, low-memory and thermal guards.

Differences that require real-model parity testing: this port conditions at 12 FPS rather than the reference's 24 FPS; uses the actual twenty latent frames in the timestep transform rather than the reference's hard-coded fifteen; and crops decoded frames to the selected duration. These are implementation decisions, not validated quality improvements. The full latent sequence is still denoised for every duration, so shorter clips do not proportionally reduce diffusion time.

## Remaining feasibility blockers

The project compiles, but no end-to-end generation has been observed. The new pipeline may still contain shape, precision, numerical, or lifetime problems detectable only with real models. It needs a fixed-prompt/seed reference comparison before optimization claims.

The local Mac has Xcode 16.4 while the paired phone runs a substantially newer beta OS. Its developer disk image could not mount. The user chose Xcode Cloud testing first. Cloud simulator tests can validate application behavior, but cannot establish phone memory limits, GPU/Neural Engine placement, thermal stability, or generated quality. A later compatible physical-device run remains necessary; it is not scheduled or silently substituted in this phase.

The evidence does not yet support a production-ready app or a promised latency on iPhone 17 Pro Max. If the partitioned model cannot fit or compile there, the practical next step is a smaller publicly released temporal model with a complete licensed decoder and a proven Core ML conversion. No hosted service or animated-still fallback is present.

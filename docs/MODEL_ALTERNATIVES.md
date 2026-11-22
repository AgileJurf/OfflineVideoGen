# Alternatives to the working MOVD engine

Research snapshot before the optional-model implementation: 21 November 2026. At the time of this ranking no alternative weights had been downloaded, converted or activated. Subsequent Neodragon conversion work and its exact validation status are recorded in [the implementation report](NEODRAGON_IMPLEMENTATION.md). This ranking is not an iPhone benchmark. The working MOVD model and library remain available.

## Recommendation

Evaluate **Neodragon** as an optional second engine first, with **LTX-Video 2B Distilled** as the next candidate. Retain MOVD until a replacement completes reproducible offline generation on the actual iPhone 17 Pro Max. A promising model family is not a drop-in upgrade to the current Core ML files.

The user’s style priority remains Anime → Photorealism → Cinematic. Model selection should precede substantial adapter integration: adapters for different model families and sizes do not interchange. No matching trained style package is assumed to exist merely because a pipeline supports LoRA.

| Candidate | Why investigate | Main limitation for LOCAL FRAMES |
| --- | --- | --- |
| MOVD / Open-Sora 1.2 | Already generated a genuine offline video on this phone; existing recovery and measured logs | Existing exports constrain conditioning, dimensions and style adapters; long measured generation path |
| Neodragon | Mobile-focused diffusion; distilled text encoder and decoder; short 24 FPS video target; public weights and inference code | Reported mobile acceleration is Qualcomm-specific. New Apple graph conversion, runtime and physical validation required |
| LTX-Video 2B Distilled | Smallest mainstream LTX-Video branch; distilled sampling and image/video conditioning paths | Large T5 encoder, different latent/decoder/scheduler contracts, and no iPhone validation established here |
| MobileWan | Mobile-oriented attention changes and three-step distillation | Approximately 5B transformer; the optimized decoder used for its mobile system is explicitly not released with this checkpoint |
| Wan 2.1 T2V 1.3B | Public weights and a comparatively small transformer | Published desktop VRAM measurements do not establish iOS memory feasibility; text encoder, activation and decoder costs remain |

## Evidence and limits

[Neodragon’s model card](https://huggingface.co/Qualcomm-AI-Research/Neodragon) reports a 0.2B distilled T5 replacement, a 4.945B full system, and approximately 3.5 GB peak RAM / 6.7 seconds for the authors’ optimized Qualcomm implementation. Its native generation target is 320 × 512 and 49 frames at 24 FPS, with a separate 2× super-resolution stage for the larger advertised output. These are **authors’ results on another platform**, not predicted LOCAL FRAMES results. The [released inference code](https://github.com/Qualcomm-AI-research/neodragon) uses a first-frame image generator followed by genuine autoregressive video diffusion in its default hybrid mode; “hybrid” there means two local model stages, not remote inference. Porting that path does not mean animating a still with camera effects. Published weights are BF16; the reported memory figure must not be assigned to those unconverted weights on iOS. The model card lists BSD-3-Clause-Clear plus [Qualcomm’s Responsible AI License](https://www.qualcomm.com/site/responsible-ai-license); distribution and upstream component terms need review before selection.

[LTX-Video](https://github.com/Lightricks/LTX-Video) provides 2B distilled weights alongside much larger 13B variants. Its [0.9.8 configuration](https://github.com/Lightricks/LTX-Video/blob/main/configs/ltxv-2b-0.9.8-distilled.yaml) has two sampling passes and a spatial upscaler; it should not be described as a measured single eight-step iPhone job. Source pipelines support image and video conditions. Its encoder and numerical behavior must be evaluated separately from the 2B transformer label. These weights use the [LTXV Open Weights License 0.X](https://huggingface.co/Lightricks/LTX-Video/blob/main/LTX-Video-Open-Weights-License-0.X.txt), not an unrestricted Apache license. Larger LTX-2.x desktop implementations are not evidence that their weights fit an iPhone.

[MobileWan’s own card](https://huggingface.co/Qualcomm-AI-Research/mobilewan) describes its modified Wan 2.2 5B transformer, three denoising steps, and 81-frame/16 FPS target. It also says the optimized decoder is not released and the sample code uses the original Wan decoder. That missing component is a material reproduction risk, so it is not the first migration choice.

[Wan 2.1 T2V 1.3B](https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B) reports 8.19 GB VRAM and a desktop GPU example. iOS app memory limits, shared system memory and thermals differ from desktop VRAM; the number does not demonstrate a working iPhone port. Its larger family’s image-to-video abilities must not be attributed automatically to this text-only checkpoint.

No alternative above has a measured speed or quality advantage over LOCAL FRAMES on the target iPhone in this investigation. Model marketing FPS, output playback FPS and generation throughput are different quantities.

## First acceptance experiment

Inspect a pinned Neodragon checkpoint and export path before downloading all optional components. Establish per-component weight size, supported operators and a conservative memory plan. Convert and compare a representative transformer stage and decoder against reference tensors; reject unsupported operations or unstable precision early. Then run one complete two-second generation on the phone, offline, with a fixed prompt and seed. Preserve original outputs and record generation time, loading time, sampled peak memory, thermal pauses and failures. Repeat the same scene set for MOVD and the candidate; same seeds across different model architectures do not imply identical latent noise or a controlled numerical comparison.

Only after successful complete generations should a separate optional model package, style adapter integration, image conditioning, longer output or native 24 FPS controls be released. Preserve originals, use per-package SHA-256 verification, require confirmation for large downloads, and keep the current engine selectable for rollback. No paid service or server-side generation is needed for this proposed experiment, but the available hardware and free compute must be verified before any training plan is adopted.

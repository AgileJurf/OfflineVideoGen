# Generation expansion: compatibility and validation

This increment adds prompt styles, explicit crop copies, saved creation settings, and capability explanations. It preserves the original MOVD weights, square inference tensors, 21 rectified-flow evaluations, decoder compute policy, baseline recovery, local library and exports. The optional support backend is unchanged. New controls are development features awaiting physical-device acceptance; simulator results do not establish video quality or iPhone performance.

## Capability decisions

| Requested capability | This build | Technical boundary / next gate |
| --- | --- | --- |
| Text to video | Existing offline pipeline preserved | Repeat the fresh two-second baseline after updating |
| Twelve visual styles | Structured text conditioning; Default leaves the model prompt unchanged | Compare every style on the physical device; no adapter or quality guarantee |
| Portrait / landscape | Explicit center-cropped copies, 144 × 256 / 256 × 144, 12 FPS | Original square video retained; native non-square inference disabled |
| Image to video | Unavailable; no misleading image-animation substitute | Missing encoder and image-conditioned transformer exports; see below |
| AI continuation | Unavailable; no unrelated clip concatenation | Requires validated reference-frame or temporal conditioning |
| 10 seconds / native 5 seconds at 24 FPS | Not enabled | Exported transformer token bounds and current decoder grouping |
| 24 FPS interpolation | Research only | Separate offline interpolation model, exact checkpoint license, conversion and device tests |
| Fast / Balanced / Quality | Not selectable | Matched performance and quality comparisons required |

## Installed contracts

The downloaded package inventory contains T5, STDiT-v3 ST/TDTM partitions, and temporal/spatial VAE **decoder** partitions. It contains no image/video VAE encoder. The app generates all initial latents from seeded noise. Its text `mask` input is not an image-conditioning mask.

All 56 ST/TDTM block input contracts omit the upstream `x_mask` and zero-timestep conditioning inputs. Part 1 produces only the regular timestep embeddings, and the final projection also omits masked-frame conditioning. Adding a Photos picker or copying pixels into a latent cannot recover these omitted operations.

The upstream [STDiT-v3 implementation](https://raw.githubusercontent.com/hpcaitech/Open-Sora/v1.2.0/opensora/models/stdit/stdit3.py) distinguishes text masks from temporal masks and applies zero-timestep modulation to conditioned frames. [Open-Sora 1.2](https://github.com/hpcaitech/Open-Sora/blob/main/docs/report_03.md) supports image-to-video and extension in its original implementation. That is evidence of a promising compatible architecture, not evidence that MOVD's exported Core ML graph implements the same path.

Reusing Open-Sora is the first candidate: convert the matching VAE encoder; restore masked timestep paths in the transformer and final projection; implement reference normalization, latent scaling, conditioning noise and per-step masks; verify the interaction with MOVD's temporal token merging and leap schedule. Compare against upstream reference tensors before device generation. Existing T5 and decoder components may be reused only after tensor/layout/scaling parity is established. Conditioned transformer artifacts need a separate versioned installation so the working exports remain available.

No deployable, device-validated image-conditioned Core ML bundle was established in this investigation. Image import, image-guided generation, extension increments, blending/combination and extension download controls remain gated by that missing model path. The app shows the reason instead of presenting an import flow that cannot generate a result. No additional large model was downloaded.

## Resolution and duration audit

Run the static audit against the previously extracted model specifications:

```sh
python3 scripts/audit_generation_capabilities.py .model-cache/model-specifications.json build/CapabilityAudit/exported-contracts.json
```

| Configuration | Latent grid / frames | Transformer tokens | Sampled input-contract failures |
| --- | --- | ---: | ---: |
| Native 256 × 256 baseline | 32 × 32 / 20 | 5,120 | 0 |
| Requested 256 × 448 | 32 × 56 / 20 | 8,960 | 32 |
| Requested 448 × 256 | 56 × 32 / 20 | 8,960 | 32 |
| 120 native frames at square resolution | 32 × 32 / 40 | 10,240 | 29 |

The inspected latent spatial bounds stop at 50; ST blocks and the final stage allow at most 7,820 tokens. These checks cover selected declared inputs, not all intermediates or positional-embedding behavior. Zero rejected contracts is not a successful inference test. Smaller non-square dimensions might fit some declarations but are not enabled without full-pipeline and device tests. The engine still assumes square dimensions in several tensor operations.

The existing decoder maps four five-latent groups to 68 frames and exports a requested prefix at 12 FPS. Seven groups would give 119 frames; reaching 120 requires eight groups with the current grouping. That exceeds transformer token bounds at 256 × 256. A support backend cannot change these local contracts.

## Pretrained candidates and licensing

| Candidate | Verified source / license declaration | Fit and deployment implication |
| --- | --- | --- |
| Open-Sora STDiT-v3 + VAE 1.2 | [Transformer weights](https://huggingface.co/hpcai-tech/OpenSora-STDiT-v3), [VAE weights](https://huggingface.co/hpcai-tech/OpenSora-VAE-v1.2): Apache-2.0 on both model cards | Best reuse candidate; preserves the T5 conditioning family and VAE conventions, but requires the missing graph paths and encoder |
| Stable Video Diffusion XT | [Model card](https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt): custom Stable Video Diffusion Community license | Different image encoder, denoiser and VAE; the card states no text control, so it does not satisfy prompt-guided motion without more work. Not selected; no redistribution or commercial-rights assumption |
| Wan 2.2 TI2V-5B | [Model card](https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B): Apache-2.0; text/image-conditioned model and weights available | Different VAE/transformer and runtime; 5B parameters imply roughly 10 GB for FP16 transformer weights alone, before encoder, decoder and activations. This is arithmetic, not a measured phone footprint. No validated iPhone Core ML package established |

The upstream [STDiT checkpoint listing](https://huggingface.co/hpcai-tech/OpenSora-STDiT-v3/tree/main) reports 4.84 GB and the [full VAE listing](https://huggingface.co/hpcai-tech/OpenSora-VAE-v1.2/tree/main) 1.57 GB. These are full source checkpoint sizes, not incremental app downloads. Exact encoder-only and conditioned-export storage, compilation space, peak memory and generation time remain unmeasured. Keep notices and verify pinned artifacts and any constituent model terms before distributing a converted package. The [MOVD code](https://github.com/eai-lab/MOVD) is MIT-licensed; this does not replace upstream weight licenses.

## Implemented behavior

- Default, Photorealistic, Cinematic, Anime, Cartoon, 3D Animation, Pixel Art, Watercolor, Claymation, Black & White, Vintage Film and Fantasy use short, visible prompt instructions. Interface thumbnails are labeled illustrations, not model samples. Style effectiveness is not yet validated.
- The original prompt and exact effective model prompt are saved separately. The bundled T5 tokenizer counts scene plus style; more than 63 tokens is rejected before model work, with no truncation. The original 500-character scene limit remains. Benchmark requests always use Default regardless of the selected creation style.
- Style, framing and seed preferences persist in a local JSON file. Reusing a video's settings restores its original scene, style, duration, framing and seed for review. The app refuses unsupported metadata/model versions instead of silently changing their conditioning.
- Every generation first saves the square original. A requested crop produces a second library item. Crop failure or cancellation preserves the original; the crop can be retried from its preview. No stretching, extra frames or upscaling is implied.
- New optional library fields include generation mode, effective prompt, style/version, framing, source-image reference, parent ID, extension history, media kind and postprocessing time. Source-image and extension fields are currently empty because those modes are unavailable. Older records/checkpoints remain readable. Parent deletion does not delete independently saved copies.
- Comparison displays style/framing and warns when model prompts differ or when a crop reuses its original's generation metrics. Export timing is separate from inference timing.
- Setup offers optional local diagnostics for Create jobs, including styled prompts and five-second requests. This records the same partition and memory/thermal measurements as the baseline, without turning an ordinary job into a resumable baseline. No report is uploaded; manual export is separate and explicitly includes prompts.

## Model management boundary

The original version-pinned, SHA-256-verified installer remains unchanged. A local capability screen shows what the installed bundle can execute. There are no fabricated optional download URLs or empty installed-model placeholders. Independent optional-package installation/removal, deduplicated shared components and verified updates will be enabled with an actual compatible package, pinned manifest, storage estimate and explicit download confirmation. Neither that future manifest service nor a network connection may be required for installed inference.

## Physical acceptance and benchmark procedure

Keep the current working model and `baseline/testflight-build-18` rollback tag. Update the app without removing its data or model. First test portrait and landscape crops of an existing square video: playback, 144 × 256 / 256 × 144 dimensions, unchanged duration/FPS, separate original, Photos/Files export, cancellation and relaunch.

Then run the unchanged fresh two-second Setup baseline at seed 42. Retain the complete journal, library metadata and MP4. A resumed session cannot supply full fresh-generation latency. Repeat the fixed Sailboat, Flag and Rolling ball cases using the protocol in [OPTIMIZATION_PHASE2.md](OPTIMIZATION_PHASE2.md).

For each style, enable local diagnostics for Create jobs, use the same scene/seed/duration, save both model prompts, and compare subject, colors, lighting, motion, background stability, flicker and adherence. Repeat selected styles at five seconds. Test a 63-token scene with Default and an overflowing styled prompt. Confirm persistence and settings reuse. After installation, enable Airplane Mode with Wi-Fi off, relaunch and repeat generation, crop, playback and export.

Record app/model revision, cold/repeat-run conditions, load/prediction/wall times, sampled peak memory, thermal states, pauses, completion status, output shape, frame count and FPS. CPU sampling is available in local journals; GPU/ANE utilization still requires compatible Instruments access. No native aspect-ratio, I2V, extension, interpolation, quantized-model performance or quality result is claimed by this increment.

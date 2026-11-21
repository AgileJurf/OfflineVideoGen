# Hybrid compute: compatibility and free-service investigation

21 November 2026. The target is local generation with optional remote assistance, retaining the complete offline engine. Media and prompt uploads require a separate explicit choice for each job. This investigation provisions no paid infrastructure, payment method, credit purchase or GPU subscription.

## Current release boundary

Build 25's support service and Enable online support setting deliver verified catalogs and explicitly consented structured diagnostics. They do not accelerate inference. A subsequent [24 FPS smoothing beta](ONLINE_SMOOTHING.md) adds a separate, direct, per-clip-consented helper integration. The production Vercel service still does not accept media or prompt data. No optimized model or replacement sampler is enabled; the new native interpolation workflow still needs physical-iPhone acceptance.

## Useful hybrid boundaries

| Stage | Device contribution | Remote contribution | Acceptance required |
| --- | --- | --- | --- |
| Transformer assistance | Tokenization, initial noise, local scheduler/CFG update, exact checkpoints, VAE decoding and MP4 writing | Matching STDiT velocity predictions at selected steps | Same checkpoint, conditioning, TDTM/ST transition, tensor shapes and precision contract; numerical parity; complete local-output tests; measured total time including network and queues |
| Prompt encoding | Diffusion, decoder and video writing remain local | Compatible T5 embeddings | Exact encoder/tokenizer and learned unconditional embedding compatibility; no substitute text model; measured net benefit |
| Frame interpolation | Genuine MOVD video generated and saved locally | RIFE intermediate frames for a separate 24 FPS copy | Same duration, correct frame count, new intermediate motion, artifact review, iPhone playback/export, explicit consent to upload that selected clip |

The current transformer executes 21 evaluations, each including 28 ST/TDTM blocks plus its first and final partitions. Retaining local denoising state would permit a hybrid predictor boundary without replacing local video generation with a cloud-only clip. Network failure must leave a recoverable local checkpoint. This boundary is a design proposal, not an implemented or measured acceleration.

Interpolation adds a postprocessing stage; it cannot be called a speedup of the original diffusion run. A 2-second 12 FPS source has 24 frames; a duration-preserving 24 FPS derivative needs 48 output frames. Relabeling the existing frames is not interpolation. Keep the original file and record the remote provider/model and derivative relationship separately.

## Free compute findings

Hugging Face currently documents two minutes of anonymous shared daily ZeroGPU time and five minutes for a free authenticated account. Hosting an owned ZeroGPU Space requires a verified personal account more than 30 days old. These are quotas with queueing, not guaranteed capacity. A new free account can use existing Spaces without satisfying the hosting-age requirement. [ZeroGPU](https://huggingface.co/docs/hub/spaces-zerogpu), [public API and quota rules](https://huggingface.co/docs/hub/spaces-api-endpoints).

The current main Inference Providers pricing documentation lists no included credits for free accounts. Older documentation snapshots still describe $0.10. Neither is a dependable free hybrid inference budget, and no paid provider was enabled. [Current provider pricing](https://huggingface.co/docs/inference-providers/main/pricing).

## Reproducible interpolation probe

The public community Space `1inkusFace/RIFE` exposes `interpolate_video` and uses Practical-RIFE. Its authors' source describes 2x interpolation and a `native` output-FPS choice. Practical-RIFE's own repository documents interpolation and MIT-licensed weights. This does not establish ownership, availability or retention guarantees for the community-hosted service. [Space source](https://huggingface.co/spaces/1inkusFace/RIFE/blob/main/app.py), [RIFE upstream](https://github.com/hzwer/Practical-RIFE).

Only a fabricated 256 × 256 moving-shapes clip was sent: 24 frames at 12 FPS for two seconds. No user recording, generated video, prompt, journal or payment data was uploaded. In the initial anonymous tests, the REST API accepted submission but returned `event: error` with no output. The official Gradio client subsequently reported a ZeroGPU quota refusal: its requested lease exceeded the remaining anonymous quota. Those attempts returned no video. The later successful browser experiment is recorded below; it does not establish generation acceleration or a working iOS integration.

Reproduction:

```sh
mkdir -p build/HybridProbe
xcrun swiftc -module-cache-path build/HybridProbe/ModuleCache -parse-as-library \
  scripts/make_interpolation_fixture.swift -o build/HybridProbe/make-fixture
build/HybridProbe/make-fixture build/HybridProbe/synthetic-12fps.mp4
node scripts/probe_hybrid_interpolation.mjs
# Optional: official-client diagnosis, with its dependency isolated from production.
npm install --prefix build/HybridProbe --ignore-scripts --no-audit --no-fund @gradio/client@2.8.0
node scripts/probe_hybrid_interpolation.mjs --client
```

Do not retry a refused quota in a loop or rotate identities to bypass it. The CLI deliberately has no credential argument. Authenticated research requires a separate explicit account workflow; do not paste access tokens into chat or commit them. Successful helper execution, privacy/retention review and physical iPhone acceptance remain gates before describing the new beta as device-validated. A public demo that sometimes answers is not a dependable application backend.

## Completed synthetic GPU experiment

The browser experiment completed using multiplier **2**, output FPS **native**, MP4, and boomerang **off**. The completed output was observed within **20.581 seconds** of submission. This is one observation and an upper bound, including queue/browser overhead; upload, download and local endpoint normalization are excluded. The service did not provide an exact GPU execution time. No paid resources were provisioned.

The Space source observed at revision `6ddbfae` declares Practical-RIFE weights `RIFEv4.26_0921.zip`. The running service's weight bytes were not independently verified. Saved input/output SHA-256 values and the complete measurements are in [acceptance.json](benchmarks/rife-synthetic-2026-11-21/acceptance.json), with settings and timing semantics in [experiment.json](benchmarks/rife-synthetic-2026-11-21/experiment.json).

| Measurement | Source | Raw service output | Locally normalized copy |
| --- | ---: | ---: | ---: |
| Resolution | 256 × 256 | 256 × 256 | 256 × 256 |
| Decoded frames | 24 | 47 | 48 |
| Nominal FPS | 12 | 24 | 24 |
| Container duration | 2.000 s | 1.959 s | 2.000 s |
| Unique decoded frames | 24 | 47 | 47 |
| File bytes | 7,490 | 15,902 | 19,646 |
| Distinct intermediate motion frames | — | 23/23 | 23/23 |
| Mean intermediate-position error | — | 0.117 px | 0.112 px |
| Maximum intermediate-position error | — | 0.368 px | 0.355 px |

The fixture translates an orange rectangle eight pixels per source frame. All 23 intervening output frames place it between its neighboring positions, with distinct decoded pixels. The raw result passes this narrow motion check, but **fails exact duration/frame-count acceptance**: it produces `2N − 1` frames. The standalone Swift probe creates a separate copy with one held terminal frame (1/24 second), producing 48 frames at exact 1/24-second timestamps. Its 23 interpolated frames are preserved through local re-encoding. That terminal hold is explicitly not an additional AI-generated frame. Both originals remain unchanged.

This establishes a functioning remote interpolation path for a fabricated translation case. It does not measure natural-scene quality, deformation, flicker, occlusion handling, iPhone memory/thermal behavior, app authentication, or MOVD inference speed. Interpolation cannot repair missing scene motion or poor prompt adherence by itself. The normalizer currently runs in the Mac probe, not the iOS app.

The compact synthetic videos are retained for independent inspection: [12 FPS input](benchmarks/rife-synthetic-2026-11-21/source-12fps.mp4), [raw RIFE result](benchmarks/rife-synthetic-2026-11-21/rife-24fps-raw.mp4), and [duration-corrected result](benchmarks/rife-synthetic-2026-11-21/rife-24fps-duration-corrected.mp4). These contain no personal content.

Reproduce the saved-result verification without any network request:

```sh
mkdir -p build/HybridProbe
xcrun swiftc -module-cache-path build/HybridProbe/ModuleCache -parse-as-library \
  scripts/verify_interpolation_fixture.swift -o build/HybridProbe/verify-interpolation
build/HybridProbe/verify-interpolation \
  docs/benchmarks/rife-synthetic-2026-11-21/source-12fps.mp4 \
  docs/benchmarks/rife-synthetic-2026-11-21/rife-24fps-raw.mp4 \
  build/HybridProbe/recheck.json \
  --normalize-endpoint build/HybridProbe/recheck-24fps.mp4
```

The tool refuses existing output/report destinations and accepts only the expected short synthetic fixture. AVFoundation decoding/encoding requires normal macOS execution; restricted automation sandboxes may lack video-codec services. Local re-encoding can produce different file hashes across OS/codec versions; compare the decoded metrics, not only compressed bytes.

## Transformer assistance: concrete compatibility gap

The official [Open-Sora demo source](https://huggingface.co/spaces/hpcai-tech/open-sora/blob/579a1b5/app.py) exposes full generation: it creates noise, encodes text, samples, decodes and returns a final video. It uses BF16 STDiT/VAE execution. It does not expose the per-step velocity operation needed to resume the app's Float32 ST/TDTM pipeline. Its documented weight family alone is insufficient to establish parity. The [STDiT-v3 model page](https://huggingface.co/hpcai-tech/OpenSora-STDiT-v3) also currently lists no Inference Provider deployment. No compatible, callable free predictor was established in this investigation, and a full remote-generation demo was not substituted.

The proposed boundary retains local T5, seeded noise, CFG/scheduler updates, checkpoints, VAE decoding and MP4 creation. A custom GPU helper would execute the exact MOVD transformer at each selected step. At the current fixed 256-square shape, an uncompressed Float32 protocol would transfer approximately:

| Tensor | Shape | Bytes |
| --- | --- | ---: |
| Text context, once per session | `[2, 1, 300, 4096]` | 9,830,400 |
| Text mask, once per session | `[1, 300]` | 1,200 |
| Latent, each request (duplicated for CFG on server) | `[1, 4, 20, 32, 32]` | 327,680 |
| Two velocity branches, each response | `[2, 4, 20, 32, 32]` | 655,360 |

For 21 remote evaluations this is about **30.48 MB**, excluding headers, scalar metadata, retries and transport overhead. These are calculated tensor sizes, not network or speed measurements. Without session context reuse, resending text would add substantial overhead. A service must preserve the first ten TDTM evaluations, final leap, timestep transform, conditional/unconditional ordering and learned null conditioning. Returned tensors require exact dimensions, finite-value checks and numerical comparison to the original partitions before any full device trial.

Free custom ZeroGPU hosting has the eligibility requirements above; an existing demo cannot be modified to return these tensors. An owned helper, pinned compatible weights, GPU parity tests and a measured device/network round trip remain prerequisites. The original offline path and Build 25 inference implementation are unchanged.

## Next acceptance work

1. Resolve a controlled helper's upload retention/deletion behavior and ordinary account authentication. The tested community Space cleans its intermediate working copies, but the reviewed source does not establish a deletion deadline for Gradio upload cache or final outputs. A Chrome login is not an iOS API credential.
2. Add an explicitly consented, per-clip **Create 24 FPS copy** workflow only after that service contract is established. Preserve the original, record provider/model provenance, validate returned duration/dimensions/frame count, and stop cleanly on quota exhaustion or network loss. The online-support toggle alone must never upload a clip.
3. Test a selected MOVD output with consent, then actual iPhone playback/export and offline fallback. Include natural motion/occlusion cases before calling the result a quality improvement.
4. For faster generation, implement the compatible velocity helper and prove numerical parity before changing the iPhone denoising path. Report end-to-end time including queues/transfers; do not infer speed gains from this RIFE test.

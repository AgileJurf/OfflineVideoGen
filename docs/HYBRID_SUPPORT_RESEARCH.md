# Hybrid compute: compatibility and free-service investigation

21 November 2026. The target is local generation with optional remote assistance, retaining the complete offline engine. Media and prompt uploads require a separate explicit choice for each job. This investigation provisions no paid infrastructure, payment method, credit purchase or GPU subscription.

## Current release boundary

The support service and Enable online support setting deliver verified catalogs and explicitly consented structured diagnostics. They do not accelerate inference. The production Vercel service does not accept media or prompt data. No hybrid helper, optimized model, replacement sampler or interpolation output has been validated on the physical iPhone by this investigation.

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

Only a fabricated 256 × 256 moving-shapes clip was sent: 24 frames at 12 FPS for two seconds. No user recording, generated video, prompt, journal, credential or payment data was used. The REST API accepted submission but returned `event: error` with no output. The official Gradio client subsequently reported a ZeroGPU quota refusal: its requested lease exceeded the remaining anonymous quota. No video was returned, so there is no quality result or acceleration measurement. The integration was not added to the iOS app as a working capability.

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

Do not retry a refused quota in a loop or rotate identities to bypass it. The CLI deliberately has no credential argument. Authenticated research requires a separate explicit account workflow; do not paste access tokens into chat or commit them. Successful helper execution, privacy/retention review and physical iPhone acceptance are still required before shipping a media-upload feature. A public demo that sometimes answers is not a validated application backend.

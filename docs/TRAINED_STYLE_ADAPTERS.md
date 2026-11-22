# Trained style adapters: compatibility audit

Reviewed 21 November 2026. Requested priority: **Anime, Photorealism, Cinematic**, in that order. The app calls the second prompt preset “Photorealistic.”

**No trained style adapter is installed or enabled by this release.** The existing twelve styles remain explicitly labeled prompt conditioning. A compatible, licensed, pretrained style checkpoint was not identified in the sources below. This is a bounded search result, not proof that no such checkpoint exists. Adding an adapter selector without executable weights would not implement the requested feature.

## The exact model boundary

The working package uses Open-Sora 1.2 **STDiT-v3**, not Open-Sora 1.3/2.0 or Open-Sora-Plan. The [upstream checkpoint configuration](https://huggingface.co/hpcai-tech/OpenSora-STDiT-v3/blob/9a8583918505ee93bd9fae8dd5ce32e1f9334c71/config.json) declares 28 spatial/temporal block pairs, hidden size 1,152, 16 attention heads, four input channels, a 1 × 2 × 2 patch, and 4,096-channel text conditioning. The app's existing T5 path and 63-token conditioning bound must remain compatible.

The [MOVD exporter](https://github.com/eai-lab/MOVD/blob/main/Device_conversion/coreml-export/stdit3/export-stdit3.py) loads that checkpoint and exports both ordinary ST and temporally merged TDTM variants. LOCAL FRAMES loads these compiled `.mlmodelc` partitions with fixed weights. Its `ModelRunner` passes activations and conditioning only; it has no adapter-weight inputs or PyTorch/PEFT runtime. A `.safetensors` LoRA cannot simply be placed beside these files and become active.

A first implementation should merge a verified adapter into the matching source transformer before conversion, then export every affected ST **and** TDTM variant from the same merged weights. Applying a style only to one path would change behavior as the leap schedule switches paths. T5 and VAE should be shared unchanged if the adapter targets only transformer attention. Changes to either component need separate compatibility and quality validation. Compiled model files must not be patched in place.

## Candidate findings

| Candidate | Finding | Decision |
| --- | --- | --- |
| Anime LoRA for MOVD / STDiT-v3 | Public Hub searches below returned no matching advertised adapter | Missing trained artifact; highest priority remains blocked at model selection |
| [Skyfallirk/anime_LoRa](https://huggingface.co/Skyfallirk/anime_LoRa) | Model card identifies SDXL 1.0 and OpenRAIL++ terms | Different base model and target layers; cannot apply its deltas to STDiT-v3 |
| [Shion1124/anime-character-lora_v1.5](https://huggingface.co/Shion1124/anime-character-lora_v1.5) | Model card identifies Stable Diffusion 1.5 UNet attention and OpenRAIL terms | Different architecture; not an offline MOVD adapter |
| [VADER Open-Sora implementation](https://github.com/mihirp1998/VADER/tree/master/VADER-Open-Sora) | Provides LoRA training/inference code for Open-Sora 1.2. Its script targets `qkv`, `q_linear`, and `kv_linear` | Relevant conversion/training reference, but no verified Anime, Photorealism or Cinematic STDiT-v3 weights established |
| [VADER published weights](https://github.com/mihirp1998/VADER/blob/master/readme.md) | The linked pretrained LoRAs are for VideoCrafter2; its Open-Sora section expects a supplied checkpoint path | VideoCrafter weights cannot be substituted into MOVD |
| [eolecvk/OpenSora-STDiT-v3-Lambda](https://huggingface.co/eolecvk/OpenSora-STDiT-v3-Lambda/tree/d658f151dc76dbac792b4f0f05c70eaefa1361ee) | Listing contains config and full model weights, without a model card or license declaration in the inspected metadata | No established style objective, provenance or redistribution permission; not selected |
| [MLX STDiT-v3](https://huggingface.co/mlx-community/OpenSora-STDiT-v3) | A format conversion of the base checkpoint | Not a trained style adapter and not a drop-in Core ML package |

The base STDiT-v3 Hub metadata declares Apache-2.0 and MOVD declares MIT. Those declarations do not license arbitrary third-party style weights or training media. VADER's code is evidence that adaptation of this base architecture is possible; it is not a verified style model or an iPhone performance result. Its documented training setup uses CUDA and a 48 GB GPU for its stated 360p/two-second configuration. That is the authors' configuration, not a universal minimum. No paid training service, new account, dataset upload or large model download was started.

## Reproducible search evidence

Public Hugging Face API requests made on the review date:

| Filter | Returned count |
| --- | ---: |
| `filter=base_model:adapter:hpcai-tech/OpenSora-STDiT-v3&limit=100` | 0 |
| `search=opensora&filter=lora&limit=100` | 0 |
| `search=opensora%20anime&limit=100` | 0 |
| `search=stdit&limit=100` | 12 |

These are queries to `https://huggingface.co/api/models`. They depend on author names/tags and can miss untagged or externally hosted weights. The twelve STDiT matches included upstream v1/v2/v3/v4 models, an MLX conversion and the Lambda listing examined above. Raw responses, timestamps, inspected configurations and exporter excerpts are retained locally in `build/AdapterAudit/`. No authentication token or personal data was used.

## Storage and deployment implications

The **existing** manifest records 8,896,191,116 compressed bytes and 9,596,423,051 expanded bytes for its transformer archive. These are baseline inventory measurements, not the size of a new adapter. Merging an adapter before conversion can require a separate copy of each changed partition; a small LoRA download does not imply a small compiled installation. Actual incremental size, compilation space, peak memory and generation time remain unmeasured until a concrete checkpoint is converted. Preserve the working bundle and share unchanged components rather than duplicating T5/VAE.

Runtime low-rank inputs are another possible design, but require new exported graphs and fresh load, memory and inference validation. That architecture change is not justified before selecting trained weights and testing the simpler merged conversion.

## Gates for an actual adapter release

1. Obtain a pretrained Anime adapter explicitly tied to the exact STDiT-v3 checkpoint (or train one using suitable licensed data and available compute). Pin the weights, base revision, license, target modules, rank, alpha and SHA-256. Reject missing/mismatched tensors rather than partially loading them. Repeat this process for Photorealism, then Cinematic.
2. Compare unmerged and merged reference outputs with fixed inputs; check all expected attention tensor shapes and finite values. Preserve the original checkpoint and export scripts. No adapter-enabled result may be labeled as the original baseline.
3. Export affected ST/TDTM partitions under a new model version, retaining existing numerical precision and inference policies initially. Compare source and Core ML tensors before device deployment; produce a real size/hash manifest.
4. Install as an explicitly confirmed optional package with independent removal and rollback. Do not offer an enabled style until the complete compatible package is available. Save adapter identity/version/strength with each new video; older records remain prompt-based.
5. Generate the same two-second scenes/seeds on the physical iPhone 17 Pro Max with Default and the trained style. Record fresh latency, sampled memory, thermal pauses, load/prediction failures and original outputs. Compare subject identity, prompt adherence, style strength, flicker and motion; then test Airplane Mode. Successful conversion or Simulator tests do not qualify as this acceptance test.

The current blocker is the missing verified pretrained style artifact, followed by conversion and physical acceptance. No quality or speed improvement is claimed. The keyboard, unified 24 FPS workflow and quota release proceed independently with the working inference engine preserved.

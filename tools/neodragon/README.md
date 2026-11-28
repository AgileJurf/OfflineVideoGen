# Neodragon conversion and validation tools

These tools operate on local, pinned pretrained weights. They do not send prompts or videos, create remote inference jobs, purchase credits, or change the optional support backend. Source weights are development inputs, not an installable iPhone package. See [the implementation/validation record](../../docs/NEODRAGON_IMPLEMENTATION.md) for current results and limitations.

## Reproducible inputs

`source-lock.json` pins the official source commit, each used source file, model revision, model files, sizes and SHA-256 values. The selected development inputs total 12,070,716,392 bytes. Download them only when that storage/network use is intended:

```sh
python3 tools/neodragon/fetch_weights.py
```

Check out `Qualcomm-AI-research/neodragon` at `d2abbe99f46577c4e1db682ad3c26832ec0c23b9` into `build/Neodragon/upstream`. Conversion checks source hashes before executing the model. Keep development weights under the ignored `.model-cache/neodragon-source` directory and generated models under ignored `build/Neodragon`.

Create a separate Python 3.12 environment and install `requirements-conversion.txt`. `requirements-lock-macos-x86_64.txt` records the exact Intel Mac environment used for the reported checks. Use local `HF_HOME` and `HF_HUB_OFFLINE=1` for conversion. The pinned original CLIP path uses BasicTokenizer, without optional `ftfy`. Native T5 is compared to the original slow SentencePiece tokenizer, not the fast tokenizer's approximate normalization.

## Stages and gates

Run each command with `--help` for its paths and options. Output directories must be new; failed candidates and reference results are not overwritten.

| Tool | Purpose |
| --- | --- |
| `probe_conversion.py` | Distilled T5 and context-adapter conversion; three fixed prompts |
| `convert_clip.py` | One of four original CLIP encoders, including complete chained pooling/penultimate comparisons |
| `make_clip_fixture.py` | Original embedding and first four-layer outputs for three prompts, used to isolate native execution from tensor-transfer errors |
| `screen_clip_precision.py` | Compare Float32, selective FP16 and finite-mask candidates against the original; native screening is a separate required check |
| `check_native_clip.swift` | Run the same original CLIP group inputs in native macOS Core ML to identify runtime-specific differences |
| `convert_transformer_aux.py` | Original timestep embedding, six positional patch variants and three output heads |
| `convert_transformer_block.py` | One original motion block; portable attention rewrite versus original, then Core ML versus original |
| `screen_long_duration.py` | Separate nine-second re-exports after all two-second block checks pass; tests minimum and maximum attention lengths |
| `check_transformer_chain.py` | Entire 18-block motion prediction against the unmodified transformer, using real prompt embeddings and deterministic latent inputs |
| `reference_ssd_unet.py`, `reference_ssd_vae.py` | Original complete SSD-1B image networks with memory-bounded weight loading |
| `convert_ssd_unet.py` | Partition and chain the image UNet or VAE against its independent complete-network reference |
| `convert_image_encoder.py` | Original video VAE image encoder, including exact T=1 causal-2D specialization |
| `convert_decoder.py` | Stateful streaming tiny video decoder, preserving original temporal history |
| `make_decoder_fixture.py` | Independent frame-by-frame Core ML reference for the Swift decoder |
| `export_sentencepiece.py` | Export the exact original SentencePiece vocabulary and compiled normalization table for native use |
| `make_*_fixture.py`, `check_*.swift` | Original token IDs, LCM math, spatial operations, temporal masks/RoPE and image preprocessing reference checks |
| `assemble_runtime.py` | Index only passing components, fingerprint every model file, copy tokenizers/plans/licenses and write runtime metadata |
| `package_release.py` | Prepare ZIP assets below 2 GB each, check decompression and SHA-256, and write a candidate manifest; never uploads or activates it |
| `inspect_video.swift` | Decode an actual export, check metadata/frame counts, retain frame hashes and inspection PNGs; pixel differences are not a quality score |
| `summarize_native_run.py` | Bind a completed native Mac run to its manifest, executable, journal and MP4 hashes; summarize partition timings and memory without uploading media |

The standard Core ML gate is finite output, matching shapes and relative L2 ≤ 0.01. Arithmetic/partition rewrites also compare against the original in PyTorch. Full FP16 T5 failed and must not be packaged; use the passing Float32 T5 candidate. The exact selected component directories are declared in `assemble_runtime.py`.

Examples after component conversion:

```sh
HF_HOME=.model-cache/huggingface HF_HUB_OFFLINE=1 build/Neodragon/convert-env/bin/python tools/neodragon/check_transformer_chain.py --seconds 2 --stage 2 --output build/Neodragon/dit-chain-2s-v1
build/Neodragon/convert-env/bin/python tools/neodragon/export_sentencepiece.py --output build/Neodragon/tokenizer-fixture/tokenizer_3/sentencepiece-native.json
python3 tools/neodragon/assemble_runtime.py --maximum-seconds 2 --output build/Neodragon/native-runtime-2s-v1
```

For nine seconds, separately re-export all motion blocks with maximum duration 9, run the complete motion-chain check at 9, and assemble with `--maximum-seconds 9`. Do not edit a two-second MLProgram's shape metadata in place or overwrite its rollback artifacts.

## Native tests

`LocalFramesTests` contains opt-in tests. Ordinary CI skips model-dependent tests and never downloads multi-gigabyte assets or uploads a clip. Configure a copy of the clean generated `.xctestrun`:

| Environment value | Meaning |
| --- | --- |
| `LOCALFRAMES_NEODRAGON_TOKENIZER_ROOT` | Folder containing `tokenizer_3/sentencepiece-native.json` |
| `LOCALFRAMES_NEODRAGON_T5_TOKENIZER_FIXTURE` | Original T5 reference JSON, including the 131-case extended set |
| `LOCALFRAMES_NEODRAGON_DECODER_FIXTURE` | Independent decoder frame/latent fixture directory |
| `LOCALFRAMES_NEODRAGON_ENGINE_FIXTURE` | Assembled runtime directory with `package-index.json` and `support/` |
| `LOCALFRAMES_NEODRAGON_ENGINE_SECONDS` | Requested native full-generation test duration; default 2 |
| `LOCALFRAMES_NEODRAGON_CLIP_FIXTURE` | Original CLIP embedding/group binary references from `make_clip_fixture.py` |
| `LOCALFRAMES_NEODRAGON_CLIP_CANDIDATES` | Precision-probe directory; native test writes a per-variant report and does not treat all variants as passing |

The complete-generation test compiles each indexed package, caches compiled models with source fingerprints, generates from the fixed sailboat prompt/seed 42, retains the MP4 and local journal, and checks duration, resolution, frame rate and frame count. Simulator CPU results are functional evidence only. Real speed, memory/thermal limits, visual quality and Airplane Mode acceptance require the physical iPhone 17 Pro Max.

`NativeCheck` is a macOS command-line harness for the same Swift engine. Build it with `swift build --package-path tools/neodragon/NativeCheck --scratch-path build/Neodragon/NativeCheckBuild -c release -j 2`, then run the resulting executable with an assembled runtime directory and duration. It explicitly requests CPU execution, stores compiled models separately from simulator artifacts, records a local journal, and checks the real MP4's duration, dimensions, rate and frame count. No upload occurs. Debug Swift builds add substantial tensor-validation overhead and must be labeled as such in any timing report. The observed Intel iOS 18.4 Simulator mixed-precision CLIP failure remains documented even when a native macOS test passes; only the target iPhone can establish device compatibility.

`NeodragonNativeCheck --verify-existing video.mp4 2` revalidates an existing two-second export and writes a separate hash-bound `export-revalidation.json`. It does not regenerate or modify the clip or its original journal. Frame checks decode image buffers: compressed AVFoundation reads may include empty marker buffers, which are not video frames.

## Publishing a candidate

The packager prepares files locally. It requires a passing complete motion-chain report at the package's maximum duration. Before publication also require a successful complete native generation and inspection of the actual clip. Include complete notices and an explicit experimental/device-validation status in the release notes. After uploading, verify the real asset URLs and hashes before releasing the app with that manifest. No model files are committed into Git or Git LFS. Keep the working Neodragon package and previous TestFlight rollback available.

## Experimental attention workspace reduction

`convert_transformer_block.py --attention-head-group-size 8` evaluates the 24 independent attention heads in three groups. It preserves the trained weights, full temporal context, causal mask and rotary positions. Zero (the default) retains the original attention graph. This is a conversion experiment, not a new checkpoint or released optimization.

```sh
HF_HOME=.model-cache/huggingface HF_HUB_OFFLINE=1 build/Neodragon/convert-env/bin/python tools/neodragon/convert_transformer_block.py --block 0 --precision mixed --maximum-seconds 9 --attention-head-group-size 8 --boundary-only --output build/Neodragon/attention-head8-block0-candidate
```

Compare every block against its original output, including the final block that returns only image features, then execute the complete chain and genuine generation. Memory comparisons must use identical input shapes, declared shape ranges, compute units and instrumentation in separate processes. A passing single-block Mac test does not validate iPhone memory use, video quality or five-second completion. The app manifest and runtime are unchanged until a separately retained candidate passes device acceptance.


## Optional attention memory trial

The `neodragon-attention-head8-v1` candidate groups the 24 independent attention
heads into three groups of eight. It retains all tokens, causal masks, temporal
positions, pretrained projections and the original hybrid sampling schedule.
The original 168-partition installation remains intact; only an explicitly
selected set of 18 motion partitions comes from the optional directory.
Generation performs no networking. Downloading this component is a separate,
user-confirmed operation with size/hash verification and sequential compilation.

Reproduce conversion for each block from 0 through 17 (replace BLOCK and NN):

```sh
build/Neodragon/convert-env/bin/python tools/neodragon/convert_transformer_block.py --block BLOCK --precision mixed --attention-head-group-size 8 --maximum-seconds 9 --boundary-only --output build/NeodragonMemoryQuality/head8-v1/block-NN
```

Run `check_transformer_chain.py --blocks build/NeodragonMemoryQuality/head8-v1`
with `--seconds 2`, `5`, and `9`, each with a new `--output` directory. Then use
`assemble_attention_variant.py --blocks ... --chain-reports ... ... ... --output ...`
and `package_release.py` with tag `neodragon-attention-head8-v1`. The assembler
checks all component identities, precision, shape ranges and chain fingerprints.
The nine-second shape check is a conversion boundary test; the app trial remains
limited to at most five seconds until actual device validation.

`measure_attention.swift` evaluates one real Core ML block with a fixed
five-second maximum input shape (1960 image tokens / 2088 total tokens), three
load/predict/release cycles and 10 ms process-memory sampling. Compare original
and candidate packages in separate processes on the same otherwise idle host.
Its synthetic-input memory results are not iPhone generation benchmarks.

The native full-generation harness accepts `--attention-runtime PATH` for the
assembled overlay and preserves the baseline fixture. It also accepts
`--upstream-detail` to compare the exact pinned upstream default prompt modifier.
That modifier is text conditioning, not fine-tuning, sharpening or a demonstrated
blur correction. Keep it off when comparing attention implementations. Preserve
original/effective prompts and use the same seed and duration for quality tests.
Do not publish a candidate download before a complete native generation passes;
do not make it the app default before the physical iPhone checks pass.

## Motion output lifetime regression

`measure_motion_lifetime.swift` isolates the recurrent Core ML output boundary.
It loads the same real motion block 24 times with synthetic activations at
1,600 image tokens, passing each prediction into the next call. Run each mode
in a fresh process against the same compiled model, using new output directories:

```sh
swiftc -O -parse-as-library tools/neodragon/measure_motion_lifetime.swift -o build/motion-lifetime
build/motion-lifetime /path/to/transformer_block_00.mlmodelc borrowed build/lifetime-borrowed
build/motion-lifetime /path/to/transformer_block_00.mlmodelc owned build/lifetime-owned
build/motion-lifetime /path/to/transformer_block_00.mlmodelc scoped-owned build/lifetime-scoped-owned
build/motion-lifetime /path/to/transformer_block_00.mlmodelc scoped-borrowed build/lifetime-scoped-borrowed
```

`borrowed` mirrors the original conversion outside the prediction autorelease
pool. `owned` adds a copy without bounding the preceding readback. The two
`scoped-` modes enclose readback, finite validation and transfer in a local pool;
`scoped-owned` also detaches the next input's storage. Compare the final
`hidden_out.bin` and `context_out.bin` byte-for-byte across runs. The app uses
the complete scoped, independent transfer only for recurrent motion outputs.

The report records process footprint at operation boundaries, not a continuous
inference peak. This repeated-block probe is not a complete video, an iPhone
benchmark, or a quality score. Native full generation and physical-device
acceptance remain separate checks. The general rationale for scoped cleanup is
documented in Apple's [autorelease-pool guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html).

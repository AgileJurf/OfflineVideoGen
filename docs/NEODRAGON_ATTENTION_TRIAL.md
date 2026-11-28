# Neodragon attention and detail comparisons

Status: local conversion and complete two-second native generation passed.
Cloud validation and the physical iPhone trial remain pending. The original
package and working profile remain the default. This document does not establish
a five-second iPhone fix or a visual-quality improvement.

All 18 converted blocks passed the minimum and maximum shape checks on the
Intel Mac. Grouped PyTorch attention matched the original outputs exactly for
those fixtures. Core ML's largest relative L2 error against Float32 PyTorch was
0.001866744 (gate: 0.01); every checked output was finite with the expected shape.
The 18 packages total 2,998,849,799 uncompressed bytes. These are component
conversion checks, not a full generation, storage-install estimate or device
performance result. Full-chain and native-generation validation remain separate.

The two-, five- and nine-second stage-three full-chain fixtures passed with
relative L2 errors of 0.001110414, 0.001120102 and 0.001275133 against the original
Float32 transformer. All three outputs were bit-identical to the installed
nine-second-range Core ML baseline for the same inputs. These are complete
motion predictions with real prompt embeddings and synthetic latent inputs;
they are not whole generated clips.

## Memory candidate

The pinned Neodragon hybrid checkpoint, mixed precision, CPU motion policy,
temporal context and one-evaluation-per-stage schedule remain unchanged. The
candidate converts each motion block to evaluate its 24 independent attention
heads in three groups of eight. Every head still sees the complete permitted
token sequence. No history window is shortened and no layers are skipped.

The optional package contains only `transformer_block_00` through
`transformer_block_17`, with its own metadata and license notices. It reuses the
other 150 base components. Installation uses resumable Wi-Fi downloads, pinned
SHA-256 and byte counts, sequential compilation and final validation before
activation in `OptionalModels/Neodragon/Variants/Head8-v1/Installed`.

The three SHA-256-verified archives total 2,355,507,732 download bytes. The
installer reserves 12,884,901,888 available bytes for archives, preparation,
compiled files and safety headroom. This is additional storage beside the
working base installation.

The original `OptionalModels/Neodragon/Installed` directory is untouched.
Selection is explicit and off by default. Removing the optional update removes
only its own installation/download cache and returns selection to the original.
Inference uses local files only; it never checks a server for eligibility or
downloads a component during a job. Both installed profiles work offline.

Frame Lab provides a two-second original baseline, a two-second attention
comparison, and a five-second attention trial. The latter two require the
separate component installation. The trial caps duration at five seconds, while
conversion parity checks also exercise the original nine-second upper shape
bound. A shape check is not a long-video generation test.

## Local single-block measurements

The current packaged candidate was compared with the original block 00 in fresh
macOS CPU-only processes. Each process performed three load/predict/release
trials using the same five-second stage-three shape (1,960 image tokens plus
128 text tokens), real weights and deterministic synthetic activations. Process
footprint was sampled every 10 ms. Both output arrays were bit-identical.

| Measurement | Original attention | Groups of eight |
| --- | ---: | ---: |
| Peak sampled footprint during prediction | 1,864,155,136 B | 829,231,104 B |
| Peak sampled footprint during model load | 1,431,478,272 B | 827,994,112 B |
| Median prediction time, three trials | 4.222 s | 3.747 s |

These measurements concern one transformer partition on the Intel Mac with
macOS 15.8.3/Core ML and a CPU-only configuration. They do not establish an
end-to-end speedup, the iPhone's whole-process memory peak, five-second completion,
or improved visual quality. Host thermal state was not recorded by this probe.
The repeated single-block outputs and full-chain parity provide numerical checks;
physical-device runs remain the acceptance gate for the application.

## Detail conditioning and blur

The [pinned reference hybrid pipeline](https://github.com/qualcomm-ai-research/neodragon/blob/d2abbe99f46577c4e1db682ad3c26832ec0c23b9/neodragon/utils/generation_utils.py)
adds a default modifier describing cinematic detail, realistic textures and
natural colors to both its first-image and motion prompts. The app's optional
**Use upstream detail prompt** setting reproduces that text conditioning.
The original user prompt remains separate from the effective model input;
all encoders still reject overlong input instead of silently truncating it.
The setting and exact effective prompt are preserved in saved-video metadata.
Reusing an older video retains its exact saved style instructions when toggling
only the detail option. Editing the scene or style invalidates that restored
conditioning instead of silently reusing stale text.

This is neither a trained adapter nor a sharpening filter. Its effect on blur,
subject identity and temporal stability requires a matched output comparison.
It can conflict aesthetically with animation or abstract styles, so it remains
optional. Keep it off during memory comparisons to change one factor at a time.

The hybrid checkpoint was distilled for one motion evaluation per stage.
The upstream multi-step model uses different transformer and context-adapter
weights plus classifier-free guidance. Increasing the current loop count is
not a checkpoint-compatible quality upgrade. No replacement weights, arbitrary
guidance setting or new sampler are installed by this change.

## Complete native Mac check

The current candidate completed a real two-second generation with the fixed
sailboat prompt and seed 42. All 168 distinct partitions executed, including all
18 optional motion blocks: 849 loads and 849 predictions, with no recorded
partition failures. AVFoundation decoded the resulting MP4 successfully:
48 frames, 512 × 320, 24 FPS, and exactly two seconds.

The CPU-only functional run took 1,579.236 seconds, with 423.583 seconds in model
loading and 957.972 seconds in prediction. Sampled peak process footprint was
3,161,071,616 bytes; the recorded thermal state was fair, with no pauses. These
are observations from an Intel Mac running other validation work, not an iPhone
benchmark or a matched speed comparison. The app still uses its established
CPU/GPU policy for shared components on the phone.

Local app validation passed 42 tests with five intentional skips. After the
saved-style comparison correction, the final unit rerun passed 36 tests with
five skips. The six UI tests include the optional controls and persistence.
Xcode Cloud will run the complete suite on the final development commit.

The separate whole-video comparison with upstream detail conditioning is still
in progress. No reduction in model blur or subject deformation is claimed.

## Validation gates

1. All 18 component exports must match the original PyTorch implementation and
   pass finite/shape/relative-error checks in Core ML.
2. Full motion-chain parity must pass at two-, five- and nine-second shapes.
   Reports and the packaged model files are bound by component fingerprints.
3. A real native Mac generation must complete before publishing the download.
   Mac results do not establish iPhone speed, memory or output equivalence.
4. App tests cover incompatible manifests, partial installations, symlinks,
   removal isolation, settings persistence and saved effective prompts.
5. Xcode Cloud must compile, analyze, test and archive the development source.
6. The physical iPhone must complete matched two-second and five-second runs,
   including offline playback/export, before treating this as a validated fix.

Reproduction commands and the native single-block memory probe are documented
in [the conversion tools](../tools/neodragon/README.md). Device journals, user
videos, account usage and private inspection reports stay outside public Git.

## Physical acceptance

Install the new TestFlight build over the current app. In Models, explicitly
download the optional attention update; do not reinstall or remove the base
model. After installation, enable Airplane Mode and disable Wi-Fi.

In Settings → Frame Lab → Run a reproducible baseline, use the same scene and
seed for the original two-second baseline and two-second attention comparison.
Keep the app foreground and starting thermal, power and charging conditions
comparable. Preserve both clips and journals. Then run the five-second trial.
Report completion or the exact final stage/error and export the benchmark files.

For blur, reuse an existing video's settings, leave the attention selection
unchanged, and compare with only **Use upstream detail prompt** toggled. Inspect
early and late frames separately. A faster run or lower memory peak does not
establish improved visual quality. Existing videos are never rewritten.

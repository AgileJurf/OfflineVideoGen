#!/usr/bin/env python3
"""Compare a complete Core ML motion prediction with the unmodified transformer.

Uses actual sailboat prompt embeddings and deterministic latent inputs. This is
an integration/parity check, not a generated video or a device speed benchmark.
"""
import argparse
import gc
import hashlib
import importlib
import json
from pathlib import Path
import resource
import time

from accelerate import init_empty_weights
import coremltools as ct
import numpy as np
from safetensors import safe_open
import torch

from convert_transformer_block import source_modules
from fetch_weights import digest, verify
from probe_conversion import compare
from reference_ssd_unet import streamed_weights

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", type=Path, default=Path("build/Neodragon"))
parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
parser.add_argument("--seconds", type=int, choices=range(2, 10), default=2)
parser.add_argument("--blocks", type=Path, help="Optional isolated candidate root containing block-00 through block-17")
parser.add_argument("--stage", type=int, choices=[0, 1, 2], default=2)
parser.add_argument("--wait-for-models", action="store_true")
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error("Use a new output directory")
args.output.mkdir(parents=True)
torch.set_num_threads(4)
torch.manual_seed(42)
lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
report = {"status": "started", "scope": __doc__, "deviceValidated": False, "seconds": args.seconds, "stage": args.stage,
          "seed": 42, "sourceRevision": lock["sourceRevision"], "weightsRevision": lock["weightsRevision"]}
try:
    for entry in lock["sourceFiles"]:
        if digest(args.source / entry["path"]) != entry["sha256"]:
            raise ValueError("Source provenance mismatch")
    for entry in lock["files"]:
        if entry["path"].startswith("diffusion_transformer_320p/") and not verify(args.weights / entry["path"], entry):
            raise ValueError("Transformer checkpoint mismatch")
    suffix = "mixed-v1" if args.seconds == 2 else "9s-mixed-v1"
    block_directories = ([args.blocks / f"block-{i:02}" for i in range(18)] if args.blocks
                         else [args.root / f"dit-block{i}-{suffix}" for i in range(18)])
    for block, directory in enumerate(block_directories):
        path = directory / "report.json"
        while not path.exists() and args.wait_for_models:
            print("Waiting for", directory.name, flush=True)
            time.sleep(30)
        if not path.exists() or json.loads(path.read_text())["status"] != "passed-component-parity":
            raise ValueError("A transformer partition has not passed: " + str(directory))
        component = json.loads(path.read_text())
        if (component["block"] != block or component["maximumSeconds"] < args.seconds
                or component["weightsRevision"] != lock["weightsRevision"]
                or component["sourceRevision"] != lock["sourceRevision"]):
            raise ValueError("Incompatible transformer partition: " + str(directory))
    report["attentionHeadGroupSize"] = component.get("attentionHeadGroupSize", 24)
    report["componentFingerprints"] = {}
    for block, directory in enumerate(block_directories):
        package = directory / f"transformer_block_{block:02}.mlpackage"
        files = [{"path": str(path.relative_to(package)), "bytes": path.stat().st_size, "sha256": digest(path)}
                 for path in sorted(package.rglob("*")) if path.is_file()]
        report["componentFingerprints"][package.stem] = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    source_modules(args.source)
    module = importlib.import_module("neodragon_source.pyramid_mmdit")
    config = json.loads((args.weights / "diffusion_transformer_320p/config.json").read_text())
    with init_empty_weights():
        model = module.PyramidMMDiT.from_config(config)
    model = model.float().eval()
    latent_count = (args.seconds * 24 - 1 + 7) // 8 + 1
    dimensions = [(10, 16), (20, 32), (40, 64)]
    scales = [max(args.stage - (latent_count - 2 - index), 0) for index in range(latent_count - 1)] + [args.stage]
    grids = [torch.randn(1, 16, 1, *dimensions[scale]) * 0.3 for scale in scales]
    context = torch.from_numpy(np.load(args.root / "context-fp16-v1/reference-0.npy", allow_pickle=False))
    pooled = torch.from_numpy(np.concatenate([np.load(args.root / f"video-clip{i}-mixed-v1/pooled-0.npy", allow_pickle=False) for i in [1, 2]], axis=1))
    token_count = json.loads(Path(__file__).with_name("fixtures").joinpath("t5-tokenizer-parity.json").read_text())["cases"][0]["count"]
    attention = torch.zeros(1, 128); attention[:, :token_count] = 1
    timestep = torch.tensor([[1000, 744, 386][args.stage]], dtype=torch.float32)
    fixture = {"seconds": args.seconds, "stage": args.stage, "scales": scales, "tokenCount": token_count,
               "scope": "Complete single motion prediction, synthetic latent inputs with real prompt embeddings"}
    for name, value in [("context", context), ("pooled", pooled)] + [(f"grid-{i}", value) for i, value in enumerate(grids)]:
        value.numpy().tofile(args.output / (name + ".bin"))
    print("Running unmodified complete transformer", flush=True)
    with safe_open(args.weights / "diffusion_transformer_320p/diffusion_pytorch_model.safetensors", framework="pt") as weights:
        # Persistent position buffers also come from the exact checkpoint.
        for path, value in list(model.named_buffers()):
            if path in weights.keys():
                parent, name = path.rsplit(".", 1)
                model.get_submodule(parent)._buffers[name] = weights.get_tensor(path).float()
        with torch.inference_mode(), streamed_weights(model, weights):
            expected = model(sample=[grids], encoder_hidden_states=context, encoder_attention_mask=attention,
                             pooled_projections=pooled, timestep_ratio=timestep)[0].numpy().copy()
    expected.tofile(args.output / "reference.bin")
    # Use the original merge_input geometry for this chain check. The native
    # geometry is independently compared in check_pyramid.swift and native tests.
    with torch.inference_mode():
        # Only position projection weights are needed for merge_input; its output
        # embeddings are not used by the Core ML chain below.
        with safe_open(args.weights / "diffusion_transformer_320p/diffusion_pytorch_model.safetensors", framework="pt") as weights:
            with streamed_weights(model.pos_embed, type("Prefixed", (), {
                "get_tensor": lambda self, key: weights.get_tensor("pos_embed." + key)})()):
                merged = model.merge_input([grids], 128, attention)
    mask = merged[-2][0].float().numpy()
    rope = merged[-1][0]
    cosine, sine = rope[..., 0, 0].numpy(), rope[..., 1, 0].numpy()
    del model, merged
    gc.collect()

    def predict(path, inputs):
        runtime = ct.models.MLModel(str(path), compute_units=ct.ComputeUnit.CPU_ONLY)
        result = runtime.predict(inputs)
        del runtime
        return result

    auxiliary = args.root / "dit-aux-mixed-v1"
    time_embedding = predict(auxiliary / "time_embedding.mlpackage", {"timestep": timestep.numpy(), "pooled": pooled.numpy()})["time_embedding"]
    patches = [predict(auxiliary / f"patch_s{scale}_p{args.stage}.mlpackage", {"latent": grid.numpy()})["hidden"]
               for scale, grid in zip(scales, grids)]
    initial_hidden = np.concatenate(patches, axis=1)

    def run_chain(directories, label):
        hidden, current_context = initial_hidden, context.numpy()
        for block, directory in enumerate(directories):
            print("Running", label, "Core ML block", block, flush=True)
            prediction = predict(directory / f"transformer_block_{block:02}.mlpackage", {"hidden": hidden, "context": current_context,
                "time_embedding": time_embedding, "attention_mask": mask, "rope_cos": cosine, "rope_sin": sine})
            hidden = prediction["hidden_out"]
            if block < 17: current_context = prediction["context_out"]
        h, w = dimensions[args.stage]
        return predict(auxiliary / f"output_s{args.stage}.mlpackage", {"hidden": hidden[:, -(h*w//4):], "time_embedding": time_embedding})["predicted_flow"]

    result = run_chain(block_directories, "candidate")
    result.tofile(args.output / "candidate.bin")
    report["parity"] = compare(result, expected)
    fixture["shape"] = list(expected.shape)
    (args.output / "fixture.json").write_text(json.dumps(fixture, indent=2) + "\n")
    if not report["parity"]["passed"]:
        raise ValueError("The complete motion chain differs from the original transformer")
    if args.blocks:
        # The installed baseline has the nine-second range even for short runs.
        baseline_directories = [args.root / f"dit-block{i}-9s-mixed-v1" for i in range(18)]
        for directory in baseline_directories:
            if json.loads((directory / "report.json").read_text())["status"] != "passed-component-parity":
                raise ValueError("Baseline conversion evidence missing")
        baseline = run_chain(baseline_directories, "installed-baseline")
        baseline.tofile(args.output / "baseline-coreml.bin")
        report["baselineCoreMLComparison"] = compare(result, baseline)
        report["baselineCoreMLComparison"]["bitIdentical"] = bool(np.array_equal(result, baseline))
        if not report["baselineCoreMLComparison"]["passed"] or report["baselineCoreMLComparison"]["relativeL2"] > 1e-5:
            raise ValueError("Attention candidate diverges from the installed Core ML baseline")
    report["status"] = "passed-chained-parity"
except Exception as error:
    import traceback
    traceback.print_exc()
    report["status"], report["error"] = "failed", f"{type(error).__name__}: {error}"
finally:
    report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(json.dumps(report, indent=2, allow_nan=False), flush=True)
if report["status"] != "passed-chained-parity":
    raise SystemExit(1)

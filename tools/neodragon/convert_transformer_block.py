#!/usr/bin/env python3
"""Screen a real Neodragon transformer block across supported pyramid lengths.

Synthetic activations test conversion, temporal masks and rotary positions. This
is not an end-to-end generated video or a physical iPhone performance benchmark.
"""
import argparse
import gc
import importlib
import json
from pathlib import Path
import platform
import resource
import sys
import time
import types

import coremltools as ct
import numpy as np
import torch
from safetensors import safe_open

from fetch_weights import digest, verify
from portable_block import PortableJointBlock
from probe_conversion import compare


def source_modules(source):
    # Import just the transformer's package, without constructing the full pipeline
    # or loading the image generator. All modules are pinned and hash checked.
    package = types.ModuleType("neodragon_source")
    package.__path__ = [str(source / "neodragon")]
    sys.modules[package.__name__] = package
    blocks = importlib.import_module("neodragon_source.pyramid_mmdit.modeling_block")
    embedding = importlib.import_module("neodragon_source.pyramid_mmdit.modeling_embedding")
    return blocks, embedding


def case_for_lengths(lengths, embeddings):
    positions = torch.cat([torch.full((length,), i, dtype=torch.float32) for i, length in enumerate(lengths)])
    times = torch.cat((torch.zeros(128), positions))[None]
    allowed = torch.cat((torch.ones(19), torch.zeros(109), torch.ones(sum(lengths))))[None]
    mask = ((allowed[:, :, None] == allowed[:, None, :]) & (times[:, :, None] >= times[:, None, :]))[:, None]
    rope = embeddings.rope(times, 64, 10000).unsqueeze(2)
    cosine = rope[..., 0, 0]
    sine = rope[..., 1, 0]
    hidden = torch.randn(1, sum(lengths), 1536) * 0.2
    context = torch.randn(1, 128, 1536) * 0.2
    time = torch.randn(1, 1536) * 0.2
    return (hidden, context, time, mask.float(), cosine, sine), rope, allowed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--block", type=int, default=0, choices=range(18))
    parser.add_argument("--precision", choices=["float16", "float32", "mixed"], default="mixed")
    parser.add_argument("--maximum-seconds", type=int, choices=range(2, 10), default=2,
                        help="Screen the largest attention shape for this duration; not a validated device preset")
    parser.add_argument("--boundary-only", action="store_true",
                        help="Check the minimum and new maximum lengths; retain the existing full two-second screen separately")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    maximum_latents = (args.maximum_seconds * 24 - 1 + 7) // 8 + 1
    maximum_lengths = [40] * (maximum_latents - 3) + [160, 640, 640]
    maximum_image_tokens = sum(maximum_lengths)
    report = {"status": "started", "block": args.block, "precision": args.precision, "seed": 42,
              "maximumSeconds": args.maximum_seconds, "maximumLatents": maximum_latents,
              "boundaryOnly": args.boundary_only,
              "torch": torch.__version__, "coremltools": ct.__version__, "host": platform.platform(),
              "sourceRevision": lock["sourceRevision"], "weightsRevision": lock["weightsRevision"],
              "deviceValidated": False, "scope": "Real weights, synthetic activations; Mac component parity only",
              "gate": "portable PyTorch relative L2 <= 1e-5; Core ML relative L2 <= 0.01; finite and matching shapes"}
    try:
        for entry in lock["sourceFiles"]:
            if digest(args.source / entry["path"]) != entry["sha256"]:
                raise ValueError("Unverified source: " + entry["path"])
        for entry in lock["files"]:
            if entry["path"].startswith("diffusion_transformer_320p/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("Unverified transformer weights/config")
        blocks, embedding = source_modules(args.source)
        print("Loading original transformer block", flush=True)
        block = blocks.JointTransformerBlock(1536, 24, 1536, qk_norm="rms_norm", context_pre_only=args.block == 17).eval()
        prefix = f"transformer_blocks.{args.block}."
        with safe_open(args.weights / "diffusion_transformer_320p/diffusion_pytorch_model.safetensors", framework="pt") as weights:
            block.load_state_dict({k.removeprefix(prefix): weights.get_tensor(k).float() for k in weights.keys() if k.startswith(prefix)}, strict=True)
        portable = PortableJointBlock(block).eval()
        inputs, references, portability = [], [], []
        lengths_to_test = [[40, 40], [160, 160], [40, 40, 40, 40, 160, 640, 640]]
        if args.maximum_seconds > 2:
            lengths_to_test.append(maximum_lengths)
        if args.boundary_only:
            lengths_to_test = [lengths_to_test[0], lengths_to_test[-1]]
        for index, lengths in enumerate(lengths_to_test):
            print(f"Checking temporal attention length {sum(lengths)}", flush=True)
            values, rope, allowed = case_for_lengths(lengths, embedding)
            with torch.inference_mode():
                context, hidden = block(values[0], values[1], allowed[:, :128], values[2],
                                        attention_mask=[values[3].bool()], hidden_length=[sum(lengths)], image_rotary_emb=[rope])
                original = (hidden,) if context is None else (hidden, context)
                actual = portable(*values)
            reference = [x.numpy().copy() for x in original]
            parity = [compare(a.numpy(), r) for a, r in zip(actual, reference)]
            if any(not p["passed"] or p["relativeL2"] > 1e-5 for p in parity):
                raise ValueError("Portable attention differs from original")
            inputs.append(values); references.append(reference); portability.append(parity)
            for i, array in enumerate(reference):
                np.save(args.output / f"reference-{index}-{i}.npy", array, allow_pickle=False)
        report["portabilityParity"] = portability
        names = ["hidden", "context", "time_embedding", "attention_mask", "rope_cos", "rope_sin"]
        output_names = ["hidden_out"] + (["context_out"] if args.block != 17 else [])
        with torch.inference_mode():
            # The boundary screen independently executes both the original and
            # portable PyTorch graphs above, then the actual Core ML graph below.
            # Avoid repeating those expensive forwards inside JIT's trace check.
            traced = torch.jit.trace(portable, inputs[0], check_inputs=inputs[1:] if not args.boundary_only else None,
                                     check_trace=not args.boundary_only, strict=True)
        length = ct.RangeDim(80, maximum_image_tokens, default=80, symbol="image_length")
        total = ct.RangeDim(208, maximum_image_tokens + 128, default=208, symbol="total_length")
        shapes = [(1, length, 1536), (1, 128, 1536), (1, 1536), (1, 1, total, total),
                  (1, total, 1, 32), (1, total, 1, 32)]
        precision = {"float16": ct.precision.FLOAT16, "float32": ct.precision.FLOAT32}.get(args.precision)
        if args.precision == "mixed":
            precision = ct.transform.FP16ComputePrecision(op_selector=lambda op: op.op_type in {"linear", "matmul"})
        print("Converting portable transformer block", flush=True)
        started = time.monotonic()
        converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                               compute_precision=precision,
                               inputs=[ct.TensorType(name=n, shape=s, dtype=np.float32) for n, s in zip(names, shapes)],
                               outputs=[ct.TensorType(name=n, dtype=np.float32) for n in output_names], skip_model_load=True)
        destination = args.output / f"transformer_block_{args.block:02}.mlpackage"
        converted.save(str(destination))
        report["conversionSeconds"] = time.monotonic() - started
        report["packageBytes"] = sum(p.stat().st_size for p in destination.rglob("*") if p.is_file())
        del portable, block, traced, converted, original, actual
        gc.collect()
        print("Running Core ML block parity", flush=True)
        runtime = ct.models.MLModel(str(destination), compute_units=ct.ComputeUnit.CPU_ONLY)
        report["cases"] = []
        for values, reference in zip(inputs, references):
            started = time.monotonic()
            result = runtime.predict({n: v.numpy() for n, v in zip(names, values)})
            parity = [compare(result[n], r) for n, r in zip(output_names, reference)]
            report["cases"].append({"imageTokens": values[0].shape[1], "outputs": parity,
                                    "macPredictionSeconds": time.monotonic() - started})
        report["status"] = "passed-component-parity" if all(p["passed"] for c in report["cases"] for p in c["outputs"]) else "failed-component-parity"
    except Exception as error:
        import traceback
        traceback.print_exc()
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(json.dumps(report, indent=2, allow_nan=False), flush=True)
    return 0 if report["status"] == "passed-component-parity" else 1


if __name__ == "__main__":
    sys.exit(main())

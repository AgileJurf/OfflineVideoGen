#!/usr/bin/env python3
"""Convert bounded SSD-1B UNet or VAE partitions and check the complete chain.

Both the partitioned PyTorch graph and chained Core ML graph must agree with the
unmodified UNet reference. This is a synthetic-conditioning conversion test.
"""
import argparse
import gc
import json
from pathlib import Path
import platform
import resource
import sys
import time

import coremltools as ct
import numpy as np
from safetensors import safe_open
import torch

from fetch_weights import verify
from probe_conversion import compare
from reference_ssd_unet import empty_unet
from ssd_unet_parts import Step, make_plan, materialize


def apply_operation(operation, values):
    if operation["operation"] == "save":
        values[operation["target"]] = values[operation["source"]]
    elif operation["operation"] == "release":
        del values[operation["slot"]]
    elif operation["operation"] == "concatenate":
        arrays = [values[name] for name in operation["inputs"]]
        values[operation["output"]] = torch.cat(arrays, dim=operation["axis"]) if isinstance(arrays[0], torch.Tensor) else np.concatenate(arrays, axis=operation["axis"])
    else:
        raise ValueError("Unknown pipeline operation")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--precision", choices=["mixed", "float32"], default="mixed")
    parser.add_argument("--component", choices=["ssd_1b_unet", "ssd_1b_vae"], default="ssd_1b_unet")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    reference_report = json.loads((args.reference / "report.json").read_text())
    if reference_report["status"] != "passed-reference-execution":
        parser.error("The unmodified component reference has not completed")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"status": "started", "deviceValidated": False, "precision": args.precision,
              "component": args.component,
              "scope": "Synthetic inputs, Mac component and chained parity; not text-to-image/video generation",
              "weightsRevision": lock["weightsRevision"], "torch": torch.__version__, "coremltools": ct.__version__,
              "host": platform.platform(), "partitions": []}
    manifest = []
    try:
        for entry in lock["files"]:
            if entry["path"].startswith(args.component + "/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("Unverified SSD-1B checkpoint")
        if reference_report["weightsRevision"] != lock["weightsRevision"]:
            raise ValueError("Reference checkpoint differs")
        if args.component == "ssd_1b_unet":
            model = empty_unet(args.weights / args.component)
            plan = make_plan(model)
            input_names = ["sample", "context", "pooled", "time_ids", "timestep"]
            output_name = "predicted_noise"
        else:
            from ssd_vae_parts import empty_vae, make_plan as make_vae_plan
            model = empty_vae(args.weights / args.component)
            plan = make_vae_plan(model)
            input_names = ["latent"]
            output_name = "decoded_image"
        source = {name: torch.from_numpy(np.load(args.reference / f"{name}.npy", allow_pickle=False))
                  for name in input_names}
        candidate = {name: value.numpy().copy() for name, value in source.items()}
        with safe_open(args.weights / args.component / "diffusion_pytorch_model.safetensors", framework="pt") as weights:
            for step in plan:
                if not isinstance(step, Step):
                    apply_operation(step, source); apply_operation(step, candidate)
                    manifest.append(step)
                    continue
                print(f"Converting and chaining {step.name}", flush=True)
                materialize(step, weights)
                inputs = tuple(source[name] for name in step.inputs)
                started = time.monotonic()
                with torch.inference_mode():
                    expected = step.module(*inputs).detach()
                    traced = torch.jit.trace(step.module, inputs)
                policy = ct.precision.FLOAT32 if args.precision == "float32" else ct.transform.FP16ComputePrecision(
                    op_selector=lambda op: op.op_type in {"conv", "linear", "matmul"})
                converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                    compute_precision=policy,
                    inputs=[ct.TensorType(name=name, shape=tuple(value.shape), dtype=np.float32) for name, value in zip(step.inputs, inputs)],
                    outputs=[ct.TensorType(name="output", dtype=np.float32)], skip_model_load=True)
                destination = args.output / (step.name + ".mlpackage")
                converted.save(str(destination))
                del traced, converted
                step.module.to("meta")
                gc.collect()
                runtime = ct.models.MLModel(str(destination), compute_units=ct.ComputeUnit.CPU_ONLY)
                result = runtime.predict({name: candidate[name] for name in step.inputs})["output"]
                parity = compare(result, expected.numpy())
                report["partitions"].append({"name": step.name, "accumulatedParity": parity,
                    "packageBytes": sum(p.stat().st_size for p in destination.rglob("*") if p.is_file()),
                    "conversionAndCheckSeconds": time.monotonic() - started})
                np.save(args.output / "last-reference.npy", expected.numpy(), allow_pickle=False)
                np.save(args.output / "last-candidate.npy", result, allow_pickle=False)
                if not parity["passed"]:
                    raise ValueError(f"Chained Core ML parity failed at {step.name}")
                source[step.output] = expected
                candidate[step.output] = result
                manifest.append({"operation": "predict", "model": step.name, "inputs": step.inputs,
                                 "output": step.output, "shape": list(expected.shape)})
                del runtime
                gc.collect()
                (args.output / "progress.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        original = np.load(args.reference / "output.npy", allow_pickle=False)
        report["partitioningParity"] = compare(source[output_name].numpy(), original)
        report["coreMLChainedParity"] = compare(candidate[output_name], original)
        if not report["partitioningParity"]["passed"] or report["partitioningParity"]["relativeL2"] > 1e-5:
            raise ValueError("Partition boundaries changed the original component output")
        if not report["coreMLChainedParity"]["passed"]:
            raise ValueError("Complete Core ML component differs from the original reference")
        (args.output / "pipeline.json").write_text(json.dumps({"component": args.component, "latentShape": [1, 4, 80, 128],
            "precision": args.precision, "steps": manifest}, indent=2) + "\n")
        report["status"] = "passed-chained-parity"
    except Exception as error:
        import traceback
        traceback.print_exc()
        report["status"], report["error"] = "failed", f"{type(error).__name__}: {error}"
    finally:
        report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(json.dumps(report, indent=2, allow_nan=False), flush=True)
    return 0 if report["status"] == "passed-chained-parity" else 1


if __name__ == "__main__":
    sys.exit(main())

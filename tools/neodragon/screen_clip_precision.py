#!/usr/bin/env python3
"""Screen first CLIP group precision variants; native results are a separate gate."""
import argparse
import gc
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from safetensors import safe_open
from transformers import CLIPTextConfig

from convert_clip import EncoderGroup, load_weights
from fetch_weights import verify
from probe_conversion import compare

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
parser.add_argument("--reference", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.output.exists(): parser.error("Use a new experiment directory")
lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
for entry in lock["files"]:
    if entry["path"].startswith("ssd_1b_text_encoder/") and not verify(args.weights / entry["path"], entry):
        raise ValueError("Source encoder fingerprint differs")
fixture = json.loads((args.reference / "fixture.json").read_text())
if fixture["weightsRevision"] != lock["weightsRevision"]: raise ValueError("Reference revision differs")
torch.set_num_threads(4)
config = CLIPTextConfig.from_pretrained(args.weights / "ssd_1b_text_encoder", local_files_only=True)
config._attn_implementation = "eager"
inputs = [np.fromfile(args.reference / case["embeddingFile"], dtype=np.float32).reshape(case["shape"]) for case in fixture["cases"]]
expected = [np.fromfile(args.reference / case["groupFile"], dtype=np.float32).reshape(case["shape"]) for case in fixture["cases"]]
args.output.mkdir(parents=True)
reports = []
for name, full, finite, matmul in [("float32", True, False, False), ("linear_fp16", False, False, False),
                                    ("finite_mask", False, True, True), ("finite_mask_linear_fp16", False, True, False)]:
    print("Converting precision probe", name, flush=True)
    module = EncoderGroup(config, 4).float().eval()
    with safe_open(args.weights / "ssd_1b_text_encoder/model.safetensors", framework="pt") as weights:
        load_weights(module, weights, [(f"text_model.encoder.layers.{i}.", f"layers.{i}.") for i in range(4)])
    if finite:
        module.causal_mask = torch.triu(torch.full((1, 1, 77, 77), -10_000.0), diagonal=1)
    with torch.inference_mode():
        portability = [compare(module(torch.from_numpy(value)).numpy(), reference) for value, reference in zip(inputs, expected)]
        for result in portability:
            result["passed"] = result["passed"] and result.get("relativeL2", float("inf")) <= 1e-5
        if not all(case["passed"] for case in portability): raise ValueError("Mask rewrite differs from the original")
        traced = torch.jit.trace(module, (torch.from_numpy(inputs[0]),))
    selected = {"linear", "gather"} | ({"matmul"} if matmul else set())
    policy = ct.precision.FLOAT32 if full else ct.transform.FP16ComputePrecision(op_selector=lambda op: op.op_type in selected)
    model = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                       compute_precision=policy, inputs=[ct.TensorType(name="hidden", shape=inputs[0].shape, dtype=np.float32)],
                       outputs=[ct.TensorType(name="hidden_out", dtype=np.float32)], skip_model_load=True)
    package = args.output / (name + ".mlpackage")
    model.save(str(package))
    del model, traced, module
    gc.collect()
    runtime = ct.models.MLModel(str(package), compute_units=ct.ComputeUnit.CPU_ONLY)
    parity = [compare(runtime.predict({"hidden": value})["hidden_out"], reference) for value, reference in zip(inputs, expected)]
    reports.append({"name": name, "packagePath": str(package.resolve()), "macPassed": all(case["passed"] for case in parity),
                    "portabilityParity": portability, "macParity": parity})
    del runtime
    gc.collect()
    (args.output / "report.json").write_text(json.dumps({"scope": __doc__, "deviceValidated": False, "variants": reports}, indent=2) + "\n")
print("Precision probes complete; native execution still required", flush=True)

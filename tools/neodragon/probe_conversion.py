#!/usr/bin/env python3
"""Convert real Neodragon components and compare deterministic reference tensors.

Development screening on the host Mac only. A passing result does not approve
an iPhone release, video quality, full-pipeline equivalence or device performance.
The official source is loaded locally from the pinned revision in source-lock.json.
"""
import argparse
import hashlib
import importlib.util
import json
import platform
import resource
import sys
import time
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

from fetch_weights import digest, verify

PROMPTS = [
    "A small sailboat glides across a calm lake at sunrise.",
    "A red flag waves gently in the wind against a blue sky.",
    "A yellow ball rolls slowly across a wooden table.",
]


def load_source(root, filename):
    spec = importlib.util.spec_from_file_location("neodragon_probe_" + Path(filename).stem,
                                                root / "neodragon" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def array_hash(value):
    return hashlib.sha256(np.ascontiguousarray(value).tobytes()).hexdigest()


def compare(result, reference):
    finite = bool(np.isfinite(result).all())
    if result.shape != reference.shape or not finite:
        return {"passed": False, "finite": finite, "shape": list(result.shape)}
    delta = result.astype(np.float64) - reference.astype(np.float64)
    relative = float(np.linalg.norm(delta) / max(np.linalg.norm(reference.astype(np.float64)), 1e-30))
    return {"passed": relative <= 0.01, "finite": finite, "shape": list(result.shape),
            "relativeL2": relative, "maxAbsoluteError": float(np.abs(delta).max()),
            "rmse": float(np.sqrt(np.mean(delta ** 2))), "outputSHA256": array_hash(result)}


def build_text(source, weights):
    from transformers import T5Tokenizer
    module = load_source(source, "distil_t5.py")
    encoder = module.T5EncoderWithProjection.from_pretrained(
        weights / "text_encoder_3", torch_dtype=torch.float32, local_files_only=True).eval()
    tokenizer = T5Tokenizer.from_pretrained(weights / "tokenizer_3", local_files_only=True)

    class Wrapper(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.encoder = encoder

        def forward(self, input_ids, attention_mask):
            return self.encoder(input_ids=input_ids, attention_mask=attention_mask)[0]

    cases = []
    for prompt in PROMPTS:
        if len(tokenizer.encode(prompt)) > 128:
            raise ValueError("Probe prompt exceeds conditioning length")
        tokens = tokenizer(prompt, max_length=128, padding="max_length", truncation=False, return_tensors="pt")
        cases.append((tokens.input_ids.to(torch.int32), tokens.attention_mask.to(torch.int32)))
    return Wrapper().eval(), ["input_ids", "attention_mask"], cases


def build_context(source, weights, text_results):
    module = load_source(source, "context_adapter.py")
    model = module.ContextAdapter.from_pretrained(weights / "context_adapter", torch_dtype=torch.float32,
                                                  local_files_only=True).eval()
    # Use the actual text encoder's embeddings, not arbitrary activations.
    cases = [(torch.from_numpy(np.load(text_results / f"reference-{i}.npy", allow_pickle=False)),)
             for i in range(len(PROMPTS))]
    return model, ["prompt_embeddings"], cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=["text_encoder_3", "context_adapter"])
    parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--text-results", type=Path)
    parser.add_argument("--precision", choices=["float32", "float16", "mixed"], default="float16")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new result directory; do not overwrite prior evidence")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    np.random.seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"component": args.component, "weightsRevision": lock["weightsRevision"],
              "sourceRevision": lock["sourceRevision"], "precision": args.precision,
              "torch": torch.__version__, "coremltools": ct.__version__, "numpy": np.__version__,
              "host": platform.platform(), "architecture": platform.machine(), "threads": 4,
              "scope": "Mac component parity; not full diffusion or iPhone validation",
              "deviceValidated": False, "prompts": PROMPTS, "seed": 42,
              "gate": "finite, matching shape and relative L2 <= 0.01 for each fixed prompt",
              "status": "started"}
    try:
        for entry in lock["sourceFiles"]:
            if digest(args.source / entry["path"]) != entry["sha256"]:
                raise ValueError("Unverified source implementation: " + entry["path"])
        required = {args.component}
        if args.component == "text_encoder_3":
            required.add("tokenizer_3")
        expected = [entry for entry in lock["files"] if entry["path"].split("/")[0] in required]
        for entry in expected:
            if not verify(args.weights / entry["path"], entry):
                raise ValueError("Unverified source weight/config: " + entry["path"])
        print("Loading reference component", flush=True)
        if args.component == "text_encoder_3":
            model, names, cases = build_text(args.source, args.weights)
        else:
            if args.text_results is None:
                raise ValueError("--text-results is required for real conditioning inputs")
            model, names, cases = build_context(args.source, args.weights, args.text_results)
        references = []
        with torch.inference_mode():
            for index, case in enumerate(cases):
                started = time.monotonic()
                reference = model(*case).detach().cpu().numpy().copy()
                if not np.isfinite(reference).all():
                    raise ValueError("Original Float32 reference produced nonfinite output")
                references.append(reference)
                np.save(args.output / f"reference-{index}.npy", reference, allow_pickle=False)
                np.savez(args.output / f"input-{index}.npz", **{name: t.numpy() for name, t in zip(names, case)})
                print(f"Reference {index}: {time.monotonic() - started:.3f} s", flush=True)
            traced = torch.jit.trace(model, cases[0], check_inputs=cases[1:], strict=True)
        print("Converting Core ML graph", flush=True)
        started = time.monotonic()
        precision = {"float16": ct.precision.FLOAT16, "float32": ct.precision.FLOAT32}.get(args.precision)
        if args.precision == "mixed":
            precision = ct.transform.FP16ComputePrecision(op_selector=lambda op: op.op_type in {"linear", "matmul"})
        converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                               compute_precision=precision,
                               inputs=[ct.TensorType(name=n, shape=tuple(t.shape), dtype=t.numpy().dtype)
                                       for n, t in zip(names, cases[0])],
                               outputs=[ct.TensorType(name="output", dtype=np.float32)], skip_model_load=True)
        destination = args.output / (args.component + ".mlpackage")
        converted.save(str(destination))
        report["conversionSeconds"] = time.monotonic() - started
        report["packageBytes"] = sum(p.stat().st_size for p in destination.rglob("*") if p.is_file())
        report["referenceHashes"] = [array_hash(x) for x in references]
        # Release tracing/reference weights before loading Core ML on this 16 GB host.
        del model, traced, converted
        import gc
        gc.collect()
        print("Running Core ML CPU parity checks", flush=True)
        started = time.monotonic()
        runtime = ct.models.MLModel(str(destination), compute_units=ct.ComputeUnit.CPU_ONLY)
        report["macLoadSeconds"] = time.monotonic() - started
        report["cases"] = []
        for index, (case, reference) in enumerate(zip(cases, references)):
            inputs = {n: t.numpy() for n, t in zip(names, case)}
            started = time.monotonic()
            result = runtime.predict(inputs)["output"]
            item = compare(result, reference)
            item["macPredictionSeconds"] = time.monotonic() - started
            report["cases"].append(item)
            np.save(args.output / f"candidate-{index}.npy", result, allow_pickle=False)
        report["status"] = "passed-component-parity" if all(x["passed"] for x in report["cases"]) else "failed-component-parity"
    except Exception as error:
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
        import traceback
        traceback.print_exc()
    finally:
        report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(json.dumps(report, indent=2, allow_nan=False), flush=True)
    return 0 if report["status"] == "passed-component-parity" else 1


if __name__ == "__main__":
    sys.exit(main())

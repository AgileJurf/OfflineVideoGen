#!/usr/bin/env python3
"""Convert the pinned transformer's time, patch-position, and output layers.

Fixed pyramid shapes use the original cropped/interpolated position embeddings.
Parity here is component arithmetic on the Mac, not generated-video validation.
"""
import argparse
import gc
import importlib
import json
from pathlib import Path
import platform
import resource
import sys

import coremltools as ct
import numpy as np
import torch
from safetensors import safe_open

from convert_transformer_block import source_modules
from fetch_weights import digest, verify
from probe_conversion import compare


class Patch(torch.nn.Module):
    def __init__(self, original, height, width, target_height, target_width):
        super().__init__()
        self.proj = original.proj
        self.register_buffer("position", original.cropped_pos_embed(height, width, target_height, target_width).clone())

    def forward(self, latent):
        return self.proj(latent[:, :, 0]).flatten(2).transpose(1, 2) + self.position


class Head(torch.nn.Module):
    def __init__(self, norm, projection, height, width):
        super().__init__()
        self.norm, self.projection = norm, projection
        self.height, self.width = height, width

    def forward(self, hidden, time_embedding):
        # Output layers are token-wise. Only the current frame is needed here;
        # the attention blocks have already included all prior latent frames.
        value = self.projection(self.norm(hidden, time_embedding))
        value = value.reshape(1, self.height // 2, self.width // 2, 2, 2, 16)
        return value.permute(0, 5, 1, 3, 2, 4).reshape(1, 16, 1, self.height, self.width)


def load(module, source, prefix):
    module.load_state_dict({key[len(prefix):]: source.get_tensor(key).float()
                           for key in source.keys() if key.startswith(prefix)}, strict=True)
    return module.eval()


def export_check(module, cases, references, names, output, path):
    with torch.inference_mode():
        traced = torch.jit.trace(module.eval(), cases[0], check_inputs=cases[1:])
    converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.transform.FP16ComputePrecision(op_selector=lambda op: op.op_type in {"linear", "matmul", "conv"}),
        inputs=[ct.TensorType(name=name, shape=tuple(value.shape), dtype=np.float32) for name, value in zip(names, cases[0])],
        outputs=[ct.TensorType(name=output, dtype=np.float32)], skip_model_load=True)
    converted.save(str(path))
    del traced, converted
    gc.collect()
    runtime = ct.models.MLModel(str(path), compute_units=ct.ComputeUnit.CPU_ONLY)
    checks = [compare(runtime.predict({n: v.numpy() for n, v in zip(names, inputs)})[output], expected)
              for inputs, expected in zip(cases, references)]
    if not all(check["passed"] for check in checks):
        raise ValueError(f"Parity failed for {path.stem}: {checks}")
    return {"name": path.stem, "cases": checks,
            "packageBytes": sum(p.stat().st_size for p in path.rglob("*") if p.is_file())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"status": "started", "seed": 42, "deviceValidated": False,
              "scope": "Mac component parity with synthetic activations; not a generated video",
              "sourceRevision": lock["sourceRevision"], "weightsRevision": lock["weightsRevision"],
              "torch": torch.__version__, "coremltools": ct.__version__, "host": platform.platform(), "partitions": []}
    try:
        for entry in lock["sourceFiles"]:
            if digest(args.source / entry["path"]) != entry["sha256"]:
                raise ValueError("Source provenance mismatch")
        for entry in lock["files"]:
            if entry["path"].startswith("diffusion_transformer_320p/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("Transformer provenance mismatch")
        _, embedding = source_modules(args.source)
        normalization = importlib.import_module("neodragon_source.pyramid_mmdit.modeling_normalization")
        with safe_open(args.weights / "diffusion_transformer_320p/diffusion_pytorch_model.safetensors", framework="pt") as weights:
            time = load(embedding.CombinedTimestepConditionEmbeddings(1536, 2048), weights, "time_text_embed.")
            cases = [(torch.tensor([float(step)]), torch.randn(1, 2048) * 0.2) for step in [1000, 744, 386]]
            with torch.inference_mode():
                refs = [time(*case).numpy().copy() for case in cases]
            report["partitions"].append(export_check(time, cases, refs, ["timestep", "pooled"], "time_embedding", args.output / "time_embedding.mlpackage"))
            del time
            gc.collect()
            position = load(embedding.PatchEmbed3D(add_temp_pos_embed=True, interp_condition_pos=True), weights, "pos_embed.")
            dimensions = [(10, 16), (20, 32), (40, 64)]
            for stage, (target_h, target_w) in enumerate(dimensions):
                for scale, (h, w) in enumerate(dimensions[:stage + 1]):
                    print(f"Converting patch scale {scale} for stage {stage}", flush=True)
                    model = Patch(position, h, w, target_h, target_w).eval()
                    cases = [(torch.randn(1, 16, 1, h, w) * 0.3,) for _ in range(3)]
                    with torch.inference_mode():
                        refs = [position.forward_func(case[0], ori_height=target_h, ori_width=target_w).flatten(1, 2).numpy().copy() for case in cases]
                        if any(compare(model(*case).numpy(), ref)["relativeL2"] > 1e-6 for case, ref in zip(cases, refs)):
                            raise ValueError("Patch position rewrite differs from the original")
                    report["partitions"].append(export_check(model, cases, refs, ["latent"], "hidden", args.output / f"patch_s{scale}_p{stage}.mlpackage"))
                    del model
            del position
            gc.collect()
            norm = load(normalization.AdaLayerNormContinuous(1536, 1536, elementwise_affine=False, eps=1e-6), weights, "norm_out.")
            projection = load(torch.nn.Linear(1536, 64), weights, "proj_out.")
            for scale, (h, w) in enumerate(dimensions):
                print(f"Converting output head scale {scale}", flush=True)
                model = Head(norm, projection, h, w).eval()
                cases = [(torch.randn(1, h * w // 4, 1536) * 0.2, torch.randn(1, 1536) * 0.2) for _ in range(3)]
                # Independently use the source's padded conditioning path and
                # unpatchification order, with preceding history included.
                refs = []
                with torch.inference_mode():
                    for hidden, time in cases:
                        history = torch.randn(1, 40, 1536) * 0.2
                        all_tokens = torch.cat((history, hidden), dim=1)
                        result = projection(norm(all_tokens, time, hidden_length=[all_tokens.shape[1]]))[:, -hidden.shape[1]:]
                        result = result.reshape(1, 1, h // 2, w // 2, 2, 2, 16)
                        result = torch.einsum("nfhwpqc->ncfhpwq", result).reshape(1, 16, 1, h, w)
                        refs.append(result.numpy().copy())
                report["partitions"].append(export_check(model, cases, refs, ["hidden", "time_embedding"], "predicted_flow", args.output / f"output_s{scale}.mlpackage"))
        report["status"] = "passed-component-parity"
    except Exception as error:
        import traceback
        traceback.print_exc()
        report["status"], report["error"] = "failed", f"{type(error).__name__}: {error}"
    finally:
        report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(json.dumps(report, indent=2, allow_nan=False), flush=True)
    return 0 if report["status"] == "passed-component-parity" else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Export Neodragon's genuine first-frame VAE encoder, including quant_conv.

The output contains Gaussian mean/log-variance, not a deterministic substitute
for the source's posterior sampling. Fixed test images are synthetic fixtures.
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


class ImageEncoder(torch.nn.Module):
    def __init__(self, encoder, quant):
        super().__init__()
        self.encoder, self.quant = encoder, quant

    def forward(self, image):
        return self.quant(self.encoder(image, is_init_image=True, temporal_chunk=False))


class OneFrameConv(torch.nn.Module):
    """Exact T=1 specialization: the causal past is zero, only the last tap contributes."""
    def __init__(self, original):
        super().__init__()
        source = original.conv
        self.padding = original.time_causal_padding[:4]
        self.conv = torch.nn.Conv2d(source.in_channels, source.out_channels, source.kernel_size[1:],
                                   stride=source.stride[1:], dilation=source.dilation[1:], groups=source.groups,
                                   bias=source.bias is not None)
        self.conv.weight = torch.nn.Parameter(source.weight[:, :, -1].detach().clone(), requires_grad=False)
        if source.bias is not None:
            self.conv.bias = torch.nn.Parameter(source.bias.detach().clone(), requires_grad=False)

    def forward(self, value, is_init_image=True, temporal_chunk=False):
        assert value.shape[2] == 1 and is_init_image and not temporal_chunk
        value = torch.nn.functional.pad(value[:, :, 0], self.padding, mode="constant")
        return self.conv(value).unsqueeze(2)


def specialize_first_frame(module, causal_type):
    for name, child in list(module.named_children()):
        if isinstance(child, causal_type):
            setattr(module, name, OneFrameConv(child).eval())
        else:
            specialize_first_frame(child, causal_type)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--precision", choices=["mixed", "float32"], default="mixed")
    parser.add_argument("--single-frame-2d", action="store_true",
                        help="Specialize causal convolutions for the supported single-image input; verify original parity")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"status": "started", "deviceValidated": False, "seed": 42, "precision": args.precision,
              "singleFrame2DSpecialization": args.single_frame_2d,
              "scope": "Mac VAE encoder component parity, synthetic images; not a generated video",
              "sourceRevision": lock["sourceRevision"], "weightsRevision": lock["weightsRevision"],
              "torch": torch.__version__, "coremltools": ct.__version__, "host": platform.platform()}
    try:
        for entry in lock["sourceFiles"]:
            if digest(args.source / entry["path"]) != entry["sha256"]:
                raise ValueError("Source provenance mismatch")
        for entry in lock["files"]:
            if entry["path"].startswith("causal_video_vae/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("VAE provenance mismatch")
        source_modules(args.source)
        module = importlib.import_module("neodragon_source.asymmetric_causal_video_vae")
        config = json.loads((args.weights / "causal_video_vae/config.json").read_text())
        encoder = module.CausalVaeEncoder(**{key.removeprefix("encoder_"): value
            for key, value in config.items() if key.startswith("encoder_")})
        quant = module.CausalConv3d(32, 32, kernel_size=1, stride=1)
        with safe_open(args.weights / "causal_video_vae/diffusion_pytorch_model.safetensors", framework="pt") as weights:
            for target, prefix in [(encoder, "encoder."), (quant, "quant_conv.")]:
                target.load_state_dict({key[len(prefix):]: weights.get_tensor(key).float()
                                       for key in weights.keys() if key.startswith(prefix)}, strict=True)
        model = ImageEncoder(encoder, quant).eval()
        x = torch.linspace(-1, 1, 512)[None, :].repeat(320, 1)
        y = torch.linspace(-1, 1, 320)[:, None].repeat(1, 512)
        cases = [torch.stack((x, y, x * y))[None, :, None], torch.rand(1, 3, 1, 320, 512) * 2 - 1]
        print("Computing original first-frame VAE encoder references", flush=True)
        with torch.inference_mode():
            references = [model(image).numpy().copy() for image in cases]
            if args.single_frame_2d:
                specialize_first_frame(model, module.CausalConv3d)
                report["specializationParity"] = [compare(model(image).numpy(), ref) for image, ref in zip(cases, references)]
                if any(not case["passed"] or case["relativeL2"] > 1e-5 for case in report["specializationParity"]):
                    raise ValueError("Single-frame specialization differs from original causal encoder")
            traced = torch.jit.trace(model, (cases[0],), check_inputs=[(cases[1],)])
        for index, (image, expected) in enumerate(zip(cases, references)):
            np.save(args.output / f"image-{index}.npy", image.numpy(), allow_pickle=False)
            np.save(args.output / f"moments-{index}.npy", expected, allow_pickle=False)
        policy = ct.precision.FLOAT32 if args.precision == "float32" else ct.transform.FP16ComputePrecision(
            op_selector=lambda op: op.op_type in {"conv", "linear", "matmul"})
        print("Converting first-frame VAE encoder", flush=True)
        converted = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
            compute_precision=policy, inputs=[ct.TensorType(name="image", shape=(1, 3, 1, 320, 512), dtype=np.float32)],
            outputs=[ct.TensorType(name="moments", dtype=np.float32)], skip_model_load=True)
        path = args.output / "image_encoder.mlpackage"
        converted.save(str(path))
        del model, encoder, quant, traced, converted
        gc.collect()
        print("Loading Core ML encoder", flush=True)
        runtime = ct.models.MLModel(str(path), compute_units=ct.ComputeUnit.CPU_ONLY)
        report["cases"] = []
        for index, (image, expected) in enumerate(zip(cases, references)):
            print(f"Predicting Core ML encoder case {index}", flush=True)
            report["cases"].append(compare(runtime.predict({"image": image.numpy()})["moments"], expected))
        report["packageBytes"] = sum(p.stat().st_size for p in path.rglob("*") if p.is_file())
        report["status"] = "passed-component-parity" if all(case["passed"] for case in report["cases"]) else "failed-component-parity"
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

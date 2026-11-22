#!/usr/bin/env python3
"""Run the unmodified SSD-1B UNet with bounded CPU weight residency.

Leaf hooks load the original parameters before use and release them after use.
No layer arithmetic is rewritten. The input is a deterministic synthetic test
case for conversion parity, not a generated image or video.
"""
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import platform
import resource
import sys
import time

from accelerate import init_empty_weights
from diffusers import UNet2DConditionModel
import numpy as np
from safetensors import safe_open
import torch

from fetch_weights import verify


def empty_unet(directory):
    config = json.loads((directory / "config.json").read_text())
    with init_empty_weights():
        model = UNet2DConditionModel.from_config(config)
    return model.float().eval()


@contextmanager
def streamed_weights(model, weights):
    hooks = []
    for path, module in model.named_modules():
        names = [name for name, _ in module.named_parameters(recurse=False)]
        if not names:
            continue

        def before(layer, inputs, prefix=path, names=names):
            for name in names:
                key = f"{prefix}.{name}" if prefix else name
                layer._parameters[name] = torch.nn.Parameter(weights.get_tensor(key).float(), requires_grad=False)

        def after(layer, inputs, outputs, names=names):
            for name in names:
                layer._parameters[name] = torch.nn.Parameter(torch.empty_like(layer._parameters[name], device="meta"), requires_grad=False)

        hooks.append(module.register_forward_pre_hook(before))
        hooks.append(module.register_forward_hook(after))
    try:
        yield
    finally:
        for hook in hooks:
            hook.remove()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"status": "started", "seed": 42, "scope": "Unmodified SSD-1B UNet, synthetic conditioning, CPU reference only",
              "deviceValidated": False, "weightsRevision": lock["weightsRevision"],
              "torch": torch.__version__, "host": platform.platform()}
    try:
        for entry in lock["files"]:
            if entry["path"].startswith("ssd_1b_unet/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("Unverified SSD-1B checkpoint")
        directory = args.weights / "ssd_1b_unet"
        model = empty_unet(directory)
        sample = torch.randn(1, 4, 80, 128)
        context = torch.randn(1, 77, 2048) * 0.2
        pooled = torch.randn(1, 1280) * 0.2
        timestep = torch.tensor([999.0])
        time_ids = torch.tensor([[640.0, 1024.0, 0.0, 0.0, 640.0, 1024.0]])
        for name, value in [("sample", sample), ("context", context), ("pooled", pooled), ("timestep", timestep), ("time_ids", time_ids)]:
            np.save(args.output / f"{name}.npy", value.numpy(), allow_pickle=False)
        started = time.monotonic()
        print("Running original SSD-1B UNet with streamed weight residency", flush=True)
        with safe_open(directory / "diffusion_pytorch_model.safetensors", framework="pt") as weights:
            with torch.inference_mode(), streamed_weights(model, weights):
                result = model(sample, timestep, encoder_hidden_states=context,
                               added_cond_kwargs={"text_embeds": pooled, "time_ids": time_ids}).sample
        array = result.numpy()
        if array.shape != (1, 4, 80, 128) or not np.isfinite(array).all():
            raise ValueError("Invalid reference output")
        np.save(args.output / "output.npy", array, allow_pickle=False)
        report["referenceSeconds"] = time.monotonic() - started
        report["status"] = "passed-reference-execution"
    except Exception as error:
        import traceback
        traceback.print_exc()
        report["status"], report["error"] = "failed", f"{type(error).__name__}: {error}"
    finally:
        report["processLifetimeMaxRSSBytes"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        (args.output / "report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
        print(json.dumps(report, indent=2, allow_nan=False), flush=True)
    return 0 if report["status"] == "passed-reference-execution" else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Export Neodragon's real video decoder as four causal, memory-bounded stages.

The partition boundaries expose the original MemBlock history explicitly. They
do not alter trained weights or substitute interpolation for video decoding.
Reference parity is checked across two latent frames (nine decoded frames).
These are synthetic latent tensors, not a text-to-video result.
"""
import argparse
import gc
import hashlib
import json
from pathlib import Path
import platform
import resource
import sys
import time

import coremltools as ct
import numpy as np
import torch
from safetensors import safe_open

from fetch_weights import digest, verify
from probe_conversion import compare, load_source


class Stage(torch.nn.Module):
    """One spatial scale, with each memory input retaining its own history."""
    def __init__(self, blocks, prefix=None, has_memory=True):
        super().__init__()
        self.prefix = torch.nn.Identity() if prefix is None else prefix
        self.one_frame = prefix is not None
        self.before = torch.nn.Sequential(*blocks[:3])
        self.has_memory = has_memory
        self.after = torch.nn.ModuleList(blocks[3:])

    def forward(self, value, past0=None, past1=None, past2=None):
        value = self.before(self.prefix(value))
        if not self.has_memory:
            for block in self.after:
                value = block(value)
            return (value,)
        next_memory = []
        for block, past in zip(self.after, (past0, past1, past2)):
            # Batch rows represent successive frames, never independent videos.
            # The first row uses saved history; later rows use the preceding input.
            # Core ML has no zero-length tensor. Stage zero has exactly one row.
            history = past if self.one_frame else torch.cat((past, value[:-1]), dim=0)
            next_memory.append(value[-1:])
            value = block(value, history)
        return value, *next_memory


def run_stream(stages, latents, coreml=False, receive=None):
    memory = [[np.zeros((1, channels, height, width), np.float32) for _ in range(3)]
              for channels, height, width in [(256, 40, 64), (128, 80, 128), (64, 160, 256)]]
    frames = []
    produced = 0

    def advance(index, value):
        nonlocal produced
        args = [value] + (memory[index] if index < 3 else [])
        if coreml:
            inputs = {"value": value, **{f"past{i}": item for i, item in enumerate(args[1:])}}
            prediction = stages[index].predict(inputs)
            result = [prediction["value_out"]] + ([prediction[f"past{i}_out"] for i in range(3)] if index < 3 else [])
        else:
            with torch.inference_mode():
                result = [item.detach().numpy().copy() for item in stages[index](*[torch.from_numpy(x) for x in args])]
        if index < 3:
            memory[index] = result[1:]
            for row in result[0]:
                advance(index + 1, row[None])
        else:
            for frame in result[0]:
                if receive is None:
                    frames.append(frame)
                elif produced >= 7:
                    receive(produced - 7, frame)
                produced += 1

    for frame in latents[0].transpose(1, 0, 2, 3):
        advance(0, frame[None])
    # Upstream causal decoder drops its seven warm-up frames, exactly once.
    return produced - 7 if receive else np.stack(frames[7:]).transpose(1, 0, 2, 3)[None]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--precision", choices=["float32", "float16"], default="float16")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output directory to preserve previous results")
    args.output.mkdir(parents=True)
    torch.set_num_threads(4)
    torch.manual_seed(42)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    report = {"status": "started", "precision": args.precision, "scope": "Mac synthetic-latent decoder parity; not a generated video",
              "deviceValidated": False, "seed": 42, "torch": torch.__version__, "coremltools": ct.__version__,
              "sourceRevision": lock["sourceRevision"], "weightsRevision": lock["weightsRevision"],
              "host": platform.platform(), "gate": "matching shape, finite and relative L2 <= 0.01"}
    try:
        for entry in lock["sourceFiles"]:
            if digest(args.source / entry["path"]) != entry["sha256"]:
                raise ValueError("Source provenance mismatch: " + entry["path"])
        for entry in lock["files"]:
            if entry["path"].startswith("causal_video_vae/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("VAE source provenance mismatch")
        module = load_source(args.source, "asymmetric_causal_video_vae/decoder.py")
        decoder = module.TAEHVDecoder().float().eval()
        with safe_open(args.weights / "causal_video_vae/diffusion_pytorch_model.safetensors", framework="pt") as weights:
            decoder.load_state_dict({key.removeprefix("decoder."): weights.get_tensor(key).float()
                                     for key in weights.keys() if key.startswith("decoder.")}, strict=True)
            post = torch.nn.Conv2d(16, 16, 1).eval()
            post.load_state_dict({"weight": weights.get_tensor("post_quant_conv.conv.weight").float().squeeze(2),
                                  "bias": weights.get_tensor("post_quant_conv.conv.bias").float()}, strict=True)
        blocks = list(decoder.blocks)
        stages = [Stage(blocks[:6], prefix=post), Stage(blocks[6:12]),
                  Stage(blocks[12:18]), Stage(blocks[18:], has_memory=False)]
        for stage in stages:
            stage.eval()
        latents = (torch.randn((1, 16, 2, 40, 64)) * 0.3).numpy()
        np.save(args.output / "latents.npy", latents, allow_pickle=False)
        report["inputSHA256"] = hashlib.sha256(latents.tobytes()).hexdigest()
        print("Computing original causal decoder reference", flush=True)
        with torch.inference_mode():
            tensor = torch.from_numpy(latents)
            quantized = post(tensor[0].permute(1, 0, 2, 3)).permute(1, 0, 2, 3)[None]
            reference = decoder(quantized).numpy().copy()
        np.save(args.output / "reference.npy", reference, allow_pickle=False)
        candidate = run_stream(stages, latents)
        report["partitioningParity"] = compare(candidate, reference)
        if not report["partitioningParity"]["passed"] or report["partitioningParity"]["relativeL2"] > 1e-5:
            raise ValueError("Exposing decoder state changed reference arithmetic")
        del candidate, decoder, blocks, quantized, tensor
        gc.collect()
        report["stages"] = []
        shapes = [(16, 40, 64, 256), (256, 40, 64, 128), (128, 80, 128, 64), (64, 160, 256, 0)]
        for index, (stage, (channels, height, width, memory_channels)) in enumerate(zip(stages, shapes)):
            print(f"Converting decoder stage {index}", flush=True)
            values = [torch.zeros((1, channels, height, width))]
            if memory_channels:
                scale = 1 if index == 0 else 2
                values += [torch.zeros((1, memory_channels, height * scale, width * scale)) for _ in range(3)]
            names = ["value"] + ([f"past{i}" for i in range(3)] if memory_channels else [])
            outputs = ["value_out"] + ([f"past{i}_out" for i in range(3)] if memory_channels else [])
            with torch.inference_mode():
                traced = torch.jit.trace(stage, tuple(values))
            started = time.monotonic()
            model = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                               compute_precision=ct.precision.FLOAT16 if args.precision == "float16" else ct.precision.FLOAT32,
                               inputs=[ct.TensorType(name=n, shape=tuple(v.shape), dtype=np.float32) for n, v in zip(names, values)],
                               outputs=[ct.TensorType(name=n, dtype=np.float32) for n in outputs], skip_model_load=True)
            path = args.output / f"decoder_stage_{index}.mlpackage"
            model.save(str(path))
            report["stages"].append({"name": path.stem, "conversionSeconds": time.monotonic() - started,
                                      "packageBytes": sum(p.stat().st_size for p in path.rglob("*") if p.is_file())})
            del traced, model
            gc.collect()
        del stages
        gc.collect()
        print("Running Core ML streaming decoder", flush=True)
        models = [ct.models.MLModel(str(args.output / f"decoder_stage_{i}.mlpackage"), compute_units=ct.ComputeUnit.CPU_ONLY)
                  for i in range(4)]
        started = time.monotonic()
        candidate = run_stream(models, latents, coreml=True)
        report["macPredictionSeconds"] = time.monotonic() - started
        report["coremlParity"] = compare(candidate, reference)
        np.save(args.output / "candidate.npy", candidate, allow_pickle=False)
        report["status"] = "passed-component-parity" if report["coremlParity"]["passed"] else "failed-component-parity"
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

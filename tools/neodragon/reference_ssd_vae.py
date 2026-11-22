#!/usr/bin/env python3
"""Run the original SSD-1B first-frame decoder for a fixed latent fixture."""
import argparse
import json
from pathlib import Path
import resource
import time
import numpy as np
from safetensors import safe_open
import torch
from fetch_weights import verify
from reference_ssd_unet import streamed_weights
from ssd_vae_parts import empty_vae

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
report = {"status": "started", "scope": "Original SSD-1B image VAE, synthetic latent; not text-to-video",
          "deviceValidated": False, "weightsRevision": lock["weightsRevision"], "seed": 42, "torch": torch.__version__}
try:
    for entry in lock["files"]:
        if entry["path"].startswith("ssd_1b_vae/") and not verify(args.weights / entry["path"], entry):
            raise ValueError("Unverified image VAE checkpoint")
    directory = args.weights / "ssd_1b_vae"
    model = empty_vae(directory)
    latent = torch.randn(1, 4, 80, 128) * 0.3
    np.save(args.output / "latent.npy", latent.numpy(), allow_pickle=False)
    started = time.monotonic()
    print("Running unmodified SSD-1B image decoder reference", flush=True)
    with safe_open(directory / "diffusion_pytorch_model.safetensors", framework="pt") as weights:
        with torch.inference_mode(), streamed_weights(model, weights):
            result = model.decode(latent / model.config.scaling_factor).sample.numpy()
    if result.shape != (1, 3, 640, 1024) or not np.isfinite(result).all():
        raise ValueError("Invalid original image decoder output")
    np.save(args.output / "output.npy", result, allow_pickle=False)
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
if report["status"] != "passed-reference-execution":
    raise SystemExit(1)

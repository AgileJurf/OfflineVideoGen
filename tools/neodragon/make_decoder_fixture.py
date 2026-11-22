#!/usr/bin/env python3
"""Write a bounded-memory reference for the opt-in native decoder test.

This is a synthetic latent fixture, never a claimed text-to-video result. Model
packages must first pass convert_decoder.py's original PyTorch comparison.
"""
import argparse
import hashlib
import json
from pathlib import Path

import coremltools as ct
import numpy as np

from convert_decoder import run_stream


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--seconds", type=int, choices=range(2, 10), default=2)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads((args.models / "report.json").read_text())
    if report["status"] != "passed-component-parity":
        parser.error("Decoder has not passed the reference conversion gate")
    args.output.mkdir(parents=True, exist_ok=False)
    count = (args.seconds * 24 - 1 + 7) // 8 + 1
    random = np.random.default_rng(42)
    latent = (random.standard_normal((1, 16, count, 40, 64)) * 0.3).astype(np.float32)
    (args.output / "normalized-latents.bin").write_bytes(latent.tobytes())
    physical = latent.copy()
    physical[:, :, :1] = physical[:, :, :1] / np.float32(0.5430) + np.float32(0.1490)
    physical[:, :, 1:] = physical[:, :, 1:] / np.float32(0.3031) + np.float32(-0.2343)
    models = [ct.models.MLModel(str(args.models / f"decoder_stage_{i}.mlpackage"), compute_units=ct.ComputeUnit.CPU_ONLY) for i in range(4)]
    hashes = []

    def receive(index, frame):
        assert frame.shape == (3, 320, 512) and np.isfinite(frame).all()
        data = np.ascontiguousarray(frame, dtype=np.float32).tobytes()
        (args.output / f"frame-{index}.bin").write_bytes(data)
        hashes.append(hashlib.sha256(data).hexdigest())

    frames = run_stream(models, physical, coreml=True, receive=receive)
    assert frames == count * 8 - 7
    fixture = {"scope": "Synthetic latent fixture; not text-to-video", "frames": frames,
               "latentFrames": count, "exportFrames": args.seconds * 24, "seed": 42,
               "modelsDirectory": str(args.models.resolve()),
               "inputSHA256": hashlib.sha256(latent.tobytes()).hexdigest(), "frameSHA256": hashes,
               "reference": "Core ML CPU decoder; separately checked against original PyTorch by convert_decoder.py"}
    (args.output / "fixture.json").write_text(json.dumps(fixture, indent=2) + "\n")
    print(f"Wrote {frames}-frame native decoder parity fixture", flush=True)


if __name__ == "__main__":
    main()

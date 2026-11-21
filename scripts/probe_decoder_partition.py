#!/usr/bin/env python3
"""Run a real Core ML partition on deterministic synthetic inputs on a Mac.

Use separate processes for each compute policy: a native Core ML abort cannot be
caught as a Python exception. This is not an iPhone or video-quality benchmark.
Requires the project's existing coremltools/numpy environment and model package.
"""
import argparse
import hashlib
import json
import platform
import time
from pathlib import Path

import coremltools as ct
import numpy as np

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path)
parser.add_argument("--compute", choices=("cpu", "cpu-gpu"), required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def event(name, **fields):
    record = {"event": name, **fields}
    print(json.dumps(record), flush=True)
    with (args.output / "events.jsonl").open("a") as stream:
        stream.write(json.dumps(record) + "\n")
        stream.flush()

units = ct.ComputeUnit.CPU_ONLY if args.compute == "cpu" else ct.ComputeUnit.CPU_AND_GPU
event("started", environment="Mac synthetic partition probe", os=platform.platform(),
      machine=platform.machine(), coremltools=ct.__version__, compute=args.compute)
started = time.monotonic()
model = ct.models.MLModel(str(args.model), compute_units=units)
# coremltools can return an object after a compiler warning with no runtime proxy.
# Do not label that case a successful load.
model.get_compiled_model_path()
event("loaded", seconds=time.monotonic() - started)
shape = (4, 512, 32, 32)
for name, values in (
    ("zeros", np.zeros(shape, dtype=np.float32)),
    ("seed42", np.random.default_rng(42).normal(0, 0.25, size=shape).astype(np.float32)),
):
    digest = hashlib.sha256(values.tobytes()).hexdigest()
    event("prediction_begin", fixture=name, shape=shape, inputSHA256=digest)
    started = time.monotonic()
    result = np.asarray(model.predict({"latents": values})["output"])
    elapsed = time.monotonic() - started
    np.save(args.output / (name + ".npy"), result)
    event("prediction_end", fixture=name, seconds=elapsed, shape=result.shape,
          dtype=str(result.dtype), finite=bool(np.isfinite(result).all()),
          outputSHA256=hashlib.sha256(result.tobytes()).hexdigest(),
          minimum=float(result.min()), maximum=float(result.max()))

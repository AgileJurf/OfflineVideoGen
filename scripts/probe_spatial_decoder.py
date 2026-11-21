#!/usr/bin/env python3
"""Exercise all original spatial VAE partitions on a Mac with synthetic input.

Run --policy cpu first. Then --policy build16 --reference <CPU output directory>
compares each partition using identical CPU-produced boundary inputs, so an
earlier numerical error or native abort does not hide later failures. CPU output
is a comparison reference, not proof of PyTorch parity or iPhone performance.
Each prediction runs in a fresh child process to isolate native Core ML crashes.
"""
import argparse
import hashlib
import json
import platform
import resource
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

PARTS = ["vae_spatial_part1", "vae_spatial_part2", "vae_spatial_part3_1",
         "vae_spatial_part3_2", "vae_spatial_part3_3", "vae_spatial_part3_4_1",
         "vae_spatial_part3_4_2", "vae_spatial_part3_4_3", "vae_spatial_part4"]

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--models", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--policy", choices=("cpu", "build16"), required=True)
parser.add_argument("--reference", type=Path)
parser.add_argument("--partition", type=int, help=argparse.SUPPRESS)
parser.add_argument("--input", type=Path, help=argparse.SUPPRESS)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)


def event(name, **fields):
    record = {"event": name, **fields}
    with (args.output / "events.jsonl").open("a") as stream:
        stream.write(json.dumps(record) + "\n")
    print(json.dumps(record), flush=True)


def digest(array):
    return hashlib.sha256(np.ascontiguousarray(array).tobytes()).hexdigest()


def cpu_only(name):
    return args.policy == "cpu" or name in ("vae_spatial_part2", "vae_spatial_part3_3") or name.startswith("vae_spatial_part3_4")


if args.partition is not None:
    import coremltools as ct
    name = PARTS[args.partition]
    values = np.load(args.input, allow_pickle=False)
    event("load_begin", partition=name, inputShape=list(values.shape), inputSHA256=digest(values),
          compute="cpuOnly" if cpu_only(name) else "cpuAndGPU", coremltools=ct.__version__)
    started = time.monotonic()
    model = ct.models.MLModel(str(args.models / (name + ".mlpackage")),
                             compute_units=ct.ComputeUnit.CPU_ONLY if cpu_only(name) else ct.ComputeUnit.CPU_AND_GPU)
    model.get_compiled_model_path()
    event("load_end", partition=name, seconds=time.monotonic() - started)
    event("predict_begin", partition=name)
    started = time.monotonic()
    result = np.asarray(model.predict({"latents": values})["output"])
    seconds = time.monotonic() - started
    np.save(args.output / (name + ".npy"), result, allow_pickle=False)
    event("predict_end", partition=name, seconds=seconds, shape=list(result.shape), dtype=str(result.dtype),
          finite=bool(np.isfinite(result).all()), nonzero=int(np.count_nonzero(result)),
          minimum=float(result.min()), maximum=float(result.max()), outputSHA256=digest(result),
          processLifetimeMaxRSSBytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    sys.exit(0 if np.isfinite(result).all() else 2)

event("started", scope="Mac synthetic spatial decoder probe; not iPhone performance or video quality",
      os=platform.platform(), machine=platform.machine(), numpy=np.__version__, policy=args.policy,
      reference=str(args.reference) if args.reference else None)
fixture = np.random.default_rng(42).normal(0, 0.25, size=(1, 4, 4, 32, 32)).astype(np.float32)
np.save(args.output / "input.npy", fixture, allow_pickle=False)
failures = 0
for index, name in enumerate(PARTS):
    source = args.reference or args.output
    input_path = source / ("input.npy" if index == 0 else PARTS[index - 1] + ".npy")
    command = [sys.executable, str(Path(__file__).resolve()), "--models", str(args.models.resolve()),
               "--output", str(args.output.resolve()), "--policy", args.policy,
               "--partition", str(index), "--input", str(input_path.resolve())]
    with (args.output / (name + ".log")).open("w") as log:
        try:
            child = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180)
            code = child.returncode
        except subprocess.TimeoutExpired:
            code = 124
    event("worker_end", partition=name, returnCode=code)
    if code != 0:
        failures += 1
        if args.reference is None:
            break
        continue
    if args.reference:
        baseline = np.load(args.reference / (name + ".npy"), allow_pickle=False)
        result = np.load(args.output / (name + ".npy"), allow_pickle=False)
        same_shape = result.shape == baseline.shape
        fields = dict(partition=name, sameShape=same_shape, referenceSHA256=digest(baseline),
                      bitExact=same_shape and result.tobytes() == baseline.tobytes())
        if same_shape:
            difference = result.astype(np.float64) - baseline.astype(np.float64)
            fields.update(maxAbsoluteError=float(np.abs(difference).max()),
                          rmse=float(np.sqrt(np.mean(difference ** 2))),
                          relativeL2=float(np.linalg.norm(difference.ravel()) / max(np.linalg.norm(baseline.astype(np.float64).ravel()), 1e-30)))
        event("comparison", **fields)
event("finished", failedWorkers=failures)
sys.exit(1 if failures else 0)

#!/usr/bin/env python3
"""Record original first-frame scheduler coefficients and independent step outputs."""
import argparse
import json
from pathlib import Path
from diffusers import LCMScheduler
import torch

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error("Use a new output path")
scheduler = LCMScheduler(set_alpha_to_one=False, original_inference_steps=4, steps_offset=1)
scheduler.set_timesteps(timesteps=[999, 749, 499, 249])
sample = torch.tensor([[[[0.5, -0.5, 2.0, -1.0]]]])
prediction = torch.tensor([[[[0.25, -0.75, 3.0, 0.1]]]])
generator = torch.Generator().manual_seed(42)
duplicate = torch.Generator().manual_seed(42)
steps = []
for index, timestep in enumerate(scheduler.timesteps):
    skip, output = scheduler.get_scalings_for_boundary_condition_discrete(timestep)
    previous = scheduler.timesteps[index + 1] if index + 1 < len(scheduler.timesteps) else timestep
    noise = torch.randn(sample.shape, generator=duplicate) if index < 3 else torch.zeros_like(sample)
    result = scheduler.step(prediction, timestep, sample, generator=generator)
    steps.append({"timestep": int(timestep), "alpha": float(scheduler.alphas_cumprod[timestep]),
                  "previousAlpha": float(scheduler.alphas_cumprod[previous]), "skip": float(skip), "output": float(output),
                  "noise": noise.flatten().tolist(), "reference": result.prev_sample.flatten().tolist()})
args.output.write_text(json.dumps({"reference": "diffusers 0.34.0 LCMScheduler with pinned Neodragon first-frame settings",
                                  "sample": sample.flatten().tolist(), "prediction": prediction.flatten().tolist(), "steps": steps}, indent=2) + "\n")
print("Wrote four original LCM scheduler step fixtures")

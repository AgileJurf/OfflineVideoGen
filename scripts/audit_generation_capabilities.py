#!/usr/bin/env python3
"""Audit exported input contracts only; this is not an inference or device test."""
import argparse
import json
from pathlib import Path


def audit(specs):
    def accepts(name, input_name, shape):
        feature = specs[name]["inputs"][input_name]
        bounds = feature.get("ranges") or [[x, x] for x in feature["shape"]]
        return len(bounds) == len(shape) and all(lo <= value <= hi for value, (lo, hi) in zip(shape, bounds))

    cases = []
    for name, width, height, latents in [
        ("square-baseline", 256, 256, 20),
        ("requested-portrait", 256, 448, 20),
        ("requested-landscape", 448, 256, 20),
        ("ten-seconds-at-12fps", 256, 256, 40),
        ("five-seconds-at-24fps-native", 256, 256, 40),
    ]:
        h, w = height // 8, width // 8
        tokens = latents * (h // 2) * (w // 2)
        failures = []
        inputs = [("stdit3_part1", "z_in", [2, 4, latents, h, w]),
                  ("stdit3_part2", "z_in", [2, 4, latents, h, w]),
                  ("stdit3_part2", "x", [2, tokens, 1152]),
                  ("vae_temporal_part1", "latents", [1, 4, 5, h, w])]
        for block in range(28):
            for kind, n in [("ST", tokens), ("TDTM", tokens // 2)]:
                inputs.append((f"stdit3_{kind}_{block}", "x", [2, n, 1152]))
        for model, feature, shape in inputs:
            if not accepts(model, feature, shape):
                failures.append({"partition": model, "input": feature, "requestedShape": shape})
        cases.append({"case": name, "width": width, "height": height, "latentFrames": latents,
                      "spatialTemporalTokens": tokens, "contractFailures": failures,
                      "deviceValidatedByThisAudit": False})
    missing = []
    for block in range(28):
        for kind in ["ST", "TDTM"]:
            name = f"stdit3_{kind}_{block}"
            if not {"x_mask", "t0"}.issubset(specs[name]["inputs"]):
                missing.append(name)
    return {"evidence": "static exported input contracts; no operations executed",
            "modelSpecificationCount": len(specs), "cases": cases,
            "blocksWithoutUpstreamTemporalConditioningInputs": missing,
            "note": "Passing sampled input contracts is necessary but does not establish complete partition, positional-embedding, memory, or device compatibility."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("specifications", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = audit(json.loads(args.specifications.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    for case in result["cases"]:
        print(f"{case['case']}: {case['spatialTemporalTokens']} tokens; {len(case['contractFailures'])} sampled input contracts rejected")
    print(f"{len(result['blocksWithoutUpstreamTemporalConditioningInputs'])} transformer blocks lack upstream image/video-conditioning inputs")

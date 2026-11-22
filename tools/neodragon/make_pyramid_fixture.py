#!/usr/bin/env python3
"""Extract masks and rotary positions from the pinned model's actual methods."""
import argparse
import hashlib
import importlib
import json
from pathlib import Path
from types import MethodType, SimpleNamespace

import torch
from convert_transformer_block import source_modules
from fetch_weights import digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("build/Neodragon/upstream"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output path")
    torch.set_num_threads(4)
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    for entry in lock["sourceFiles"]:
        if digest(args.source / entry["path"]) != entry["sha256"]:
            raise ValueError("Source provenance mismatch")
    source_modules(args.source)
    original = importlib.import_module("neodragon_source.pyramid_mmdit")
    proxy = SimpleNamespace(patch_size=2, pos_embed_type="sincos", temp_pos_embed_type="rope",
                            add_temp_pos_embed=True, use_temporal_causal=True,
                            temp_rope_embed=original.EmbedNDRoPE(1536, 10000, [64]))
    for method in ["_prepare_temporal_rope_ids", "_prepare_pyramid_temporal_rope_ids"]:
        setattr(proxy, method, MethodType(getattr(original.PyramidMMDiT, method), proxy))
    # Only token count is consumed by merge_input when building masks. Learned
    # patch values are deliberately absent from this geometry-only fixture.
    proxy.pos_embed = lambda samples: [torch.empty(1, sum(t.shape[2] * t.shape[3] * t.shape[4] // 4 for t in sample), 1) for sample in samples]
    report = {"sourceRevision": lock["sourceRevision"], "cases": []}
    for shapes in [[(1, 10, 16), (1, 10, 16)], [(4, 10, 16), (1, 20, 32), (1, 40, 64), (1, 40, 64)],
                   [(25, 10, 16), (1, 20, 32), (1, 40, 64), (1, 40, 64)]]:
        sample = [[torch.zeros(1, 16, t, h, w) for t, h, w in shapes]]
        allowed = torch.cat((torch.ones(19), torch.zeros(109)))[None]
        result = original.PyramidMMDiT.merge_input(proxy, sample, 128, allowed)
        mask, rotation = result[-2][0], result[-1][0]
        length = mask.shape[-1]
        locations = sorted(set([0, 18, 19, 127, 128, length // 2, length - 1]))
        report["cases"].append({"lengths": [h * w // 4 for t, h, w in shapes for _ in range(t)],
            "textTokenCount": 19, "maskSHA256": hashlib.sha256(mask.float().numpy().tobytes()).hexdigest(),
            "rotary": [{"token": index, "cosine": rotation[0, index, 0, :, 0, 0].tolist(),
                         "sine": rotation[0, index, 0, :, 1, 0].tolist()} for index in locations]})
    value = torch.arange(192, dtype=torch.float32).reshape(1, 2, 8, 12) / 37 - 2
    down = torch.nn.functional.interpolate(value, size=(4, 6), mode="bilinear")
    up = torch.nn.functional.interpolate(value, scale_factor=2, mode="nearest")
    report["grid"] = {"channels": 2, "height": 8, "width": 12, "values": value.flatten().tolist(),
                      "downsample": down.flatten().tolist(), "upsample": up.flatten().tolist()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print("Wrote original model geometry fixtures through nine seconds")


if __name__ == "__main__":
    main()

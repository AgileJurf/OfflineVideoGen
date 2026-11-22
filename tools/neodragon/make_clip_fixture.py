#!/usr/bin/env python3
"""Original first-image CLIP embedding/group fixtures for native diagnostics."""
import argparse
import gc
import json
from pathlib import Path

import torch
from safetensors import safe_open
from transformers import CLIPTextConfig, CLIPTokenizer

from convert_clip import Embedding, EncoderGroup, load_weights
from fetch_weights import verify
from probe_conversion import PROMPTS

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error("Use a new reference directory")
lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
for entry in lock["files"]:
    if entry["path"].split("/")[0] in {"ssd_1b_text_encoder", "ssd_1b_tokenizer"} and not verify(args.weights / entry["path"], entry):
        raise ValueError("Reference input fingerprint differs")
torch.set_num_threads(4)
config = CLIPTextConfig.from_pretrained(args.weights / "ssd_1b_text_encoder", local_files_only=True)
config._attn_implementation = "eager"
tokenizer = CLIPTokenizer.from_pretrained(args.weights / "ssd_1b_tokenizer", local_files_only=True)
tokens = [tokenizer(text, max_length=77, padding="max_length", truncation=False, return_tensors="pt").input_ids.to(torch.int32) for text in PROMPTS]
args.output.mkdir(parents=True)
cases = []
with safe_open(args.weights / "ssd_1b_text_encoder/model.safetensors", framework="pt") as weights:
    embedding = Embedding(config).float().eval()
    load_weights(embedding, weights, [("text_model.embeddings.", "embedding.")])
    with torch.inference_mode():
        hidden = [embedding(ids).detach().clone() for ids in tokens]
    positions = embedding.embedding.position_ids.tolist()[0]
    del embedding
    gc.collect()
    group = EncoderGroup(config, 4).float().eval()
    load_weights(group, weights, [(f"text_model.encoder.layers.{i}.", f"layers.{i}.") for i in range(4)])
    for index, value in enumerate(hidden):
        with torch.inference_mode():
            expected = group(value).numpy().copy()
        value.numpy().tofile(args.output / f"embedding-{index}.bin")
        expected.tofile(args.output / f"layers-0-3-{index}.bin")
        cases.append({"prompt": PROMPTS[index], "inputIDs": tokens[index].tolist()[0], "shape": list(value.shape),
                      "embeddingFile": f"embedding-{index}.bin", "groupFile": f"layers-0-3-{index}.bin"})
report = {"scope": __doc__, "weightsRevision": lock["weightsRevision"], "dtype": "little-endian-float32",
          "runtimePositionIDs": positions, "cases": cases}
(args.output / "fixture.json").write_text(json.dumps(report, indent=2) + "\n")
print("Original CLIP fixtures ready:", len(cases), flush=True)

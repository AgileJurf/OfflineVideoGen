#!/usr/bin/env python3
"""Create real-vocabulary CLIP parity cases for the native tokenizer."""
import argparse
import json
from pathlib import Path

from transformers import CLIPTokenizer
from fetch_weights import verify

PROMPTS = ["A small sailboat glides across a calm lake at sunrise.",
           "A red flag waves gently in the wind against a blue sky.",
           "A yellow ball rolls slowly across a wooden table.",
           "It's a cat's toy; we've seen it! Don't blink.",
           "A café at sunrise. CAFE\u0301 at night.",
           "中文，山水，猫。", "日本の桜 and 서울 city", "🙂 A boat ⛵️ in the rain!",
           "12345, 1.5 and 24 FPS", "  a\tboat\n\non water\u00a0 ",
           "!!! bright!!!", "<|startoftext|>waves<|endoftext|>",
           "a\u0000\u200b\uFFFDboat", "", "a photorealistic red sailboat, cinematic lighting"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new output path")
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    cases = []
    for name in ["tokenizer", "tokenizer_2", "ssd_1b_tokenizer", "ssd_1b_tokenizer_2"]:
        for entry in lock["files"]:
            if entry["path"].startswith(name + "/") and not verify(args.weights / entry["path"], entry):
                raise ValueError("Unverified tokenizer assets")
        tokenizer = CLIPTokenizer.from_pretrained(args.weights / name, local_files_only=True)
        if tokenizer.fix_text is not None:
            raise ValueError("Reference must use the pinned BasicTokenizer path without optional ftfy")
        for prompt in PROMPTS:
            ids = tokenizer(prompt, max_length=77, padding="max_length", truncation=False).input_ids
            assert len(ids) == 77
            cases.append({"tokenizer": name, "text": prompt, "ids": ids})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"weightsRevision": lock["weightsRevision"], "reference": "transformers 4.46.3 CLIPTokenizer, BasicTokenizer without ftfy",
                                     "cases": cases}, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {len(cases)} tokenizer cases")


if __name__ == "__main__":
    main()

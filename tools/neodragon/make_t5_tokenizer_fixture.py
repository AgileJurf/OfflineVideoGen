#!/usr/bin/env python3
"""Create pinned original T5 IDs to check native prompt conditioning."""
import argparse
import json
import random
import unicodedata
from pathlib import Path
from transformers import T5Tokenizer
from make_tokenizer_fixture import PROMPTS
from fetch_weights import verify

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--extended", action="store_true")
args = parser.parse_args()
if args.output.exists():
    parser.error("Use a new output path")
lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
for entry in lock["files"]:
    if entry["path"].startswith("tokenizer_3/") and not verify(args.weights / entry["path"], entry):
        raise ValueError("Unverified T5 tokenizer assets")
tokenizer = T5Tokenizer.from_pretrained(args.weights / "tokenizer_3", local_files_only=True)
cases = []
prompts = PROMPTS + ["A sailboat.</s>", "A sailboat <extra_id_0> on water."]
if args.extended:
    prompts += ["ắ", "a\u0306\u0301", "한", "ﬁ K ① ＨＥＬＬＯ ～ ™", "👩🏽‍🚀👨‍👩‍👧‍👦", "🙂🚀猫狗猫",
                "<pad>boat</s>", "<extra_id_0><extra_id_99>", "a<unk><unk>b", " \t\n ",
                "\u0000\u0001a\u001eb\u007f", "a\u200db\u200cc\u2060d", "▁boat▁water", "<extra_id_3>  boat  <extra_id_4>"]
    rng = random.Random(42)
    words = ["boat", "sailboat", "glides", "water", "café", "ắ", "서울", "中文", "🙂", "🚀", "rain", "frame24",
             "①", "K", "™", "山", "a\u0306\u0301", "\u0000", "\u200b", "!", "don't", "it's", "<extra_id_2>"]
    separators = [" ", "  ", "\t", "\n", "\u00a0", "\u3000", ""]
    for index in range(100):
        text = "".join(rng.choice(words) + rng.choice(separators) for _ in range(rng.randrange(1, 14)))
        prompts.append(unicodedata.normalize("NFD", text) if index % 2 else text)
for prompt in prompts:
    result = tokenizer(prompt, max_length=128, padding="max_length", truncation=False)
    assert len(result.input_ids) == 128
    cases.append({"text": prompt, "ids": result.input_ids, "count": sum(result.attention_mask)})
args.output.write_text(json.dumps({"weightsRevision": lock["weightsRevision"], "cases": cases}, ensure_ascii=False, indent=2) + "\n")
print(f"Wrote {len(cases)} T5 tokenizer parity cases")

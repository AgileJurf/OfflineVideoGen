#!/usr/bin/env python3
"""Export the pinned slow T5 SentencePiece model without changing its rules."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
from sentencepiece import sentencepiece_model_pb2

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
if args.output.exists():
    parser.error("Preserve the existing tokenizer export")
source = args.weights / "tokenizer_3/spiece.model"
blob = source.read_bytes()
sha = hashlib.sha256(blob).hexdigest()
lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
assert sha == next(item["sha256"] for item in lock["files"] if item["path"] == "tokenizer_3/spiece.model")
model = sentencepiece_model_pb2.ModelProto()
model.ParseFromString(blob)
normalizer = model.normalizer_spec
assert model.trainer_spec.model_type == 1 and not model.trainer_spec.byte_fallback
assert normalizer.add_dummy_prefix and normalizer.remove_extra_whitespaces and normalizer.escape_whitespaces
assert not model.trainer_spec.treat_whitespace_as_suffix
assert all(piece.type in [1, 2, 3] for piece in model.pieces), "This runtime does not support user-defined/byte pieces"
config = json.loads((args.weights / "tokenizer_3/tokenizer_config.json").read_text())
assert config["legacy"] is True and config["add_prefix_space"] is True
data = {"schemaVersion": 1, "sourceSHA256": sha, "reference": "SentencePiece 0.2.1; transformers 4.46.3 T5Tokenizer legacy=True",
        "normalizer": {"name": normalizer.name, "precompiledCharsmap": base64.b64encode(normalizer.precompiled_charsmap).decode(),
                       "addDummyPrefix": True, "removeExtraWhitespaces": True, "escapeWhitespaces": True},
        "vocabulary": [{"text": piece.piece, "score": piece.score, "type": piece.type} for piece in model.pieces],
        "addedTokens": [{"id": int(key), **value} for key, value in config["added_tokens_decoder"].items()],
        "unknownID": model.trainer_spec.unk_id, "eosID": model.trainer_spec.eos_id, "paddingID": model.trainer_spec.pad_id}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
print(json.dumps({"vocabulary": len(model.pieces), "sourceSHA256": sha, "outputBytes": args.output.stat().st_size}))

#!/usr/bin/env python3
"""Index an optional attention conversion without replacing any base components.

Requires all 18 converted blocks and full-chain parity at two, five and nine
seconds. This is conversion evidence, not physical iPhone generation validation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from assemble_runtime import digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=Path, required=True)
    parser.add_argument("--chain-reports", type=Path, nargs=3, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new directory; preserve previous evidence")
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    chains = [json.loads(path.read_text()) for path in args.chain_reports]
    if ({c["seconds"] for c in chains} != {2, 5, 9}
            or any(c["status"] != "passed-chained-parity" or c["stage"] != 2 or c["attentionHeadGroupSize"] != 8
                   or not c.get("baselineCoreMLComparison", {}).get("passed")
                   or c["baselineCoreMLComparison"]["relativeL2"] > 1e-5 for c in chains)):
        raise ValueError("The complete candidate chain must pass at 2, 5 and 9 seconds")
    models = []
    for block in range(18):
        directory = args.blocks / f"block-{block:02}"
        report = json.loads((directory / "report.json").read_text())
        if (report["status"] != "passed-component-parity" or report["block"] != block
                or report["attentionHeadGroupSize"] != 8 or report["maximumSeconds"] != 9
                or report["precision"] != "mixed" or report["weightsRevision"] != lock["weightsRevision"]
                or report["sourceRevision"] != lock["sourceRevision"]):
            raise ValueError("Unvalidated or incompatible attention component")
        name = f"transformer_block_{block:02}"
        package = directory / (name + ".mlpackage")
        files = []
        for path in sorted(package.rglob("*")):
            if path.is_symlink():
                raise ValueError("Symlink in candidate package")
            if path.is_file():
                files.append({"path": str(path.relative_to(package)), "bytes": path.stat().st_size, "sha256": digest(path)})
        fingerprint = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if any(chain["componentFingerprints"].get(name) != fingerprint for chain in chains):
            raise ValueError("The chain evidence refers to different model files")
        models.append({"name": name, "packagePath": str(package.resolve()), "bytes": sum(f["bytes"] for f in files),
                       "fingerprint": fingerprint, "files": files})
    support = args.output / "support"
    support.mkdir(parents=True)
    metadata = {"schemaVersion": 1, "variantID": "neodragon-attention-head8-v1", "baseModelID": lock["modelID"],
                "sourceRevision": lock["sourceRevision"], "weightsRevision": lock["weightsRevision"],
                "attentionHeadGroupSize": 8, "maximumSeconds": 9, "modelNames": [m["name"] for m in models]}
    (support / "neodragon-attention.json").write_text(json.dumps(metadata, indent=2) + "\n")
    shutil.copyfile(Path(__file__).with_name("THIRD-PARTY-NOTICES.txt"), support / "THIRD-PARTY-NOTICES.txt")
    index = {"maximumSeconds": 9, "attentionVariant": metadata, "models": models,
             "packageBytes": sum(m["bytes"] for m in models), "deviceValidated": False,
             "chainReportSHA256": [digest(p) for p in args.chain_reports]}
    (args.output / "package-index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"Indexed {len(models)} attention components; {index['packageBytes']} bytes. Original package unchanged.")


if __name__ == "__main__":
    main()

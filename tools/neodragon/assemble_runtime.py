#!/usr/bin/env python3
"""Assemble only parity-passing Neodragon components for a local native test.

This writes an index, copied support files, and package fingerprints. It neither
publishes a download nor marks the model as validated on an iPhone.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("build/Neodragon"))
    parser.add_argument("--weights", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--maximum-seconds", type=int, choices=[2, 9], required=True)
    parser.add_argument("--ssd-clip1-directory", default="ssd-clip1-mixed-v3",
                        help="First-image CLIP-L conversion; Float32 is available as a separate diagnostic candidate")
    parser.add_argument("--sentencepiece", type=Path, default=Path("build/Neodragon/tokenizer-fixture/tokenizer_3/sentencepiece-native.json"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if Path(args.ssd_clip1_directory).name != args.ssd_clip1_directory or args.ssd_clip1_directory in {".", ".."}:
        parser.error("The CLIP candidate must be a directory name within --root")
    if args.output.exists():
        parser.error("Use a new output directory; existing evidence is preserved")
    source_lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    sentencepiece = json.loads(args.sentencepiece.read_text())
    if sentencepiece["sourceSHA256"] != next(item["sha256"] for item in source_lock["files"] if item["path"] == "tokenizer_3/spiece.model"):
        raise ValueError("SentencePiece export does not match the pinned model")
    suffix = "mixed-v1" if args.maximum_seconds == 2 else "9s-mixed-v1"
    components = ["text-fp32-v1", "context-fp16-v1", "video-clip1-mixed-v1", "video-clip2-mixed-v1",
                  args.ssd_clip1_directory, "ssd-clip2-mixed-v1", "dit-aux-mixed-v1", "decoder-fp16-v2",
                  "image-encoder-2d-mixed-v1", "ssd-unet-mixed-v1", "ssd-vae-mixed-v1"]
    components += [f"dit-block{i}-{suffix}" for i in range(18)]
    # Check the complete image networks and every video component before even
    # creating the fixture. Complete motion-chain/video results are separate.
    reports = []
    for component in components:
        path = args.root / component / "report.json"
        report = json.loads(path.read_text())
        if report["status"] not in ["passed-component-parity", "passed-chained-parity"]:
            raise ValueError(f"Unvalidated component: {component}")
        if "9s-" in component and report.get("maximumSeconds") != 9:
            raise ValueError("The long-duration attention bounds were not validated")
        reports.append({"directory": component, "reportSHA256": digest(path), "status": report["status"]})
    args.output.mkdir(parents=True)
    support = args.output / "support"
    support.mkdir()
    models = []
    names = set()
    total = 0
    for component in components:
        directory = args.root / component
        for package in sorted(directory.glob("*.mlpackage")):
            if package.stem in names:
                raise ValueError("Duplicate model " + package.stem)
            names.add(package.stem)
            files = []
            for item in sorted(package.rglob("*")):
                if item.is_symlink():
                    raise ValueError("Symlink in model package")
                if item.is_file():
                    files.append({"path": str(item.relative_to(package)), "bytes": item.stat().st_size, "sha256": digest(item)})
            fingerprint = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
            size = sum(item["bytes"] for item in files)
            total += size
            models.append({"name": package.stem, "packagePath": str(package.resolve()), "bytes": size,
                           "fingerprint": fingerprint, "files": files})
            print("Indexed", package.stem, size, flush=True)
        plan_path = directory / "pipeline.json"
        if plan_path.exists():
            plan = json.loads(plan_path.read_text())
            shutil.copyfile(plan_path, support / (plan["component"] + "_pipeline.json"))
    tokenizer_directories = {"tokenizer", "tokenizer_2", "tokenizer_3", "ssd_1b_tokenizer", "ssd_1b_tokenizer_2"}
    for entry in source_lock["files"]:
        relative = Path(entry["path"])
        if relative.parts[0] not in tokenizer_directories:
            continue
        source = args.weights / relative
        if source.stat().st_size != entry["bytes"] or digest(source) != entry["sha256"]:
            raise ValueError("Tokenizer provenance differs: " + str(relative))
        destination = support / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    shutil.copyfile(args.sentencepiece, support / "tokenizer_3/sentencepiece-native.json")
    shutil.copyfile(Path(__file__).with_name("THIRD-PARTY-NOTICES.txt"), support / "THIRD-PARTY-NOTICES.txt")
    runtime = {"schemaVersion": 1, "modelID": source_lock["modelID"], "sourceRevision": source_lock["sourceRevision"],
               "weightsRevision": source_lock["weightsRevision"], "conversionVersion": 1,
               "maximumSeconds": args.maximum_seconds, "modelNames": sorted(names)}
    (support / "neodragon-runtime.json").write_text(json.dumps(runtime, indent=2) + "\n")
    index = {"schemaVersion": 1, "maximumSeconds": args.maximum_seconds, "packageBytes": total,
             "deviceValidated": False, "reports": reports, "models": models}
    (args.output / "package-index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(json.dumps({"models": len(models), "packageBytes": total, "maximumSeconds": args.maximum_seconds}))


if __name__ == "__main__":
    main()

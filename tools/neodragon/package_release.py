#!/usr/bin/env python3
"""Prepare bounded, SHA-256 verified optional-model release archives locally.

Does not publish assets or modify the app's bundled manifest. A release needs
separate complete-generation evidence, asset upload, URL verification and an
explicit experimental/device-validation status in its release notes.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import zipfile


def checksum(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--chain-report", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--minimum-app-version", default="0.1.0")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new release directory; never replace previous assets")
    if not args.tag.startswith("neodragon-") or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-." for c in args.tag):
        parser.error("Use a lowercase neodragon- release tag")
    index = json.loads((args.runtime / "package-index.json").read_text())
    variant = index.get("attentionVariant")
    metadata = variant or json.loads((args.runtime / "support/neodragon-runtime.json").read_text())
    chain = json.loads(args.chain_report.read_text())
    if chain["status"] != "passed-chained-parity" or chain["seconds"] != index["maximumSeconds"]:
        raise ValueError("The complete motion prediction has not passed at the requested maximum duration")
    if metadata["maximumSeconds"] != index["maximumSeconds"] or set(metadata["modelNames"]) != {m["name"] for m in index["models"]}:
        raise ValueError("Runtime model index differs")
    if variant and (args.tag != variant["variantID"] or chain["componentFingerprints"] != {m["name"]: m["fingerprint"] for m in index["models"]}):
        raise ValueError("Attention variant identity or validated components differ")
    groups = [{"models": [], "supportFiles": [], "files": [], "directories": [], "bytes": 0}]
    for source in sorted((args.runtime / "support").rglob("*")):
        if source.is_symlink():
            raise ValueError("Support symlinks are not allowed")
        if source.is_file():
            relative = str(source.relative_to(args.runtime / "support"))
            groups[0]["supportFiles"].append(relative)
            size = source.stat().st_size
            groups[0]["files"].append((source, relative, size, checksum(source)))
            groups[0]["bytes"] += size
    for model in index["models"]:
        if groups[-1]["bytes"] + model["bytes"] > 1_400_000_000:
            groups.append({"models": [], "supportFiles": [], "files": [], "directories": [], "bytes": 0})
        group = groups[-1]
        if model["bytes"] > 1_400_000_000:
            raise ValueError("A model package exceeds the conservative archive bound")
        group["models"].append(model["name"])
        package_root = Path(model["packagePath"])
        # Even a weightless MLProgram can reference an empty weights directory
        # in Manifest.json. Omitting it makes Core ML reject the whole package.
        for directory in sorted(package_root.rglob("*")):
            if directory.is_symlink():
                raise ValueError("Model package symlinks are not allowed")
            if directory.is_dir():
                group["directories"].append(model["name"] + ".mlpackage/" + str(directory.relative_to(package_root)) + "/")
        for item in model["files"]:
            source = Path(model["packagePath"]) / item["path"]
            if source.is_symlink() or source.stat().st_size != item["bytes"]:
                raise ValueError("Model source changed")
            group["files"].append((source, model["name"] + ".mlpackage/" + item["path"], item["bytes"], item["sha256"]))
        group["bytes"] += model["bytes"]
    args.output.mkdir(parents=True)
    archives = []
    for offset, group in enumerate(groups):
        name = f"neodragon-{offset + 1:02}.zip"
        archive = args.output / name
        print("Writing", name, group["bytes"], "expanded bytes", flush=True)
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1, allowZip64=True) as destination:
            for relative in group["directories"]:
                path = PurePosixPath(relative)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe archive directory")
                info = zipfile.ZipInfo(relative, date_time=(2026, 11, 21, 0, 0, 0))
                info.external_attr = (0o40755 << 16) | 0x10
                destination.writestr(info, b"")
            for source, relative, size, expected_hash in group["files"]:
                path = PurePosixPath(relative)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Unsafe archive path")
                info = zipfile.ZipInfo(relative, date_time=(2026, 11, 21, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                # CPython 3.12's streaming ZipInfo API uses this per-entry field.
                info._compresslevel = 1
                info.external_attr = 0o100644 << 16
                info.file_size = size
                sha = hashlib.sha256()
                with source.open("rb") as stream, destination.open(info, "w", force_zip64=False) as target:
                    for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
                        sha.update(block)
                        target.write(block)
                if sha.hexdigest() != expected_hash:
                    raise ValueError("Model source fingerprint changed while archiving: " + relative)
        size = archive.stat().st_size
        if size >= 2_000_000_000:
            raise ValueError("Archive exceeds the download host bound")
        # CRC verifies decompression independently of the SHA over transport bytes.
        with zipfile.ZipFile(archive) as check:
            if check.testzip() is not None or sum(item.file_size for item in check.infolist()) != group["bytes"]:
                raise ValueError("Archive decompression verification failed")
            members = set(check.namelist())
            for model in group["models"]:
                base = model + ".mlpackage/"
                package_manifest = json.loads(check.read(base + "Manifest.json"))
                for entry in package_manifest["itemInfoEntries"].values():
                    expected = base + "Data/" + entry["path"]
                    if expected not in members and expected + "/" not in members:
                        raise ValueError("A model manifest entry is missing from the archive: " + expected)
        archives.append({"name": name, "url": f"https://github.com/AgileJurf/OfflineVideoGen/releases/download/{args.tag}/{name}",
                         "bytes": size, "expandedBytes": group["bytes"], "sha256": checksum(archive),
                         "models": group["models"], "supportFiles": group["supportFiles"]})
        print("Verified", name, size, "download bytes", flush=True)
    reserve = sum(a["bytes"] for a in archives) + index["packageBytes"] * 2 + max(g["bytes"] for g in groups) + 2 * 1024**3
    manifest = {"schemaVersion": 1, "modelID": metadata.get("modelID", metadata.get("baseModelID")), "modelVersion": args.tag,
                "weightsRevision": metadata["weightsRevision"], "sourceRevision": metadata["sourceRevision"],
                "maximumSeconds": metadata["maximumSeconds"], "minimumAppVersion": args.minimum_app_version,
                "minimumFreeBytes": math.ceil(reserve / 1024**3) * 1024**3, "archives": archives}
    if variant:
        manifest["attentionVariant"] = variant
    (args.output / ("neodragon-attention-manifest.json" if variant else "neodragon-manifest.json")).write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"archives": len(archives), "downloadBytes": sum(a["bytes"] for a in archives),
                      "minimumFreeBytes": manifest["minimumFreeBytes"], "status": "prepared-locally-not-published"}), flush=True)


if __name__ == "__main__":
    main()

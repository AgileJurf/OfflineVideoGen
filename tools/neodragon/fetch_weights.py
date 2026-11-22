#!/usr/bin/env python3
"""Fetch pinned Neodragon reference weights for LOCAL FRAMES conversion.

These PyTorch files are development inputs, not an installable iPhone model.
No account, remote inference, payment, prompt or video upload is involved.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            checksum.update(block)
    return checksum.hexdigest()


def verify(path, entry):
    return path.is_file() and path.stat().st_size == entry["bytes"] and digest(path) == entry["sha256"]


def fetch(entry, root, revision, transport="curl"):
    relative = PurePosixPath(entry["path"])
    if relative.is_absolute() or ".." in relative.parts or str(relative) != entry["path"]:
        raise ValueError("Unsafe source path")
    expected = f"https://huggingface.co/Qualcomm-AI-Research/Neodragon/resolve/{revision}/{relative}"
    if entry["url"] != expected:
        raise ValueError("Unpinned source URL")
    target = root.joinpath(*relative.parts)
    if verify(target, entry):
        print(f"Verified cached {relative}", flush=True)
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if transport == "hub":
        from huggingface_hub import hf_hub_download
        print(f"Fetching {relative} ({entry['bytes']:,} bytes) with the official Hub client", flush=True)
        result = Path(hf_hub_download("Qualcomm-AI-Research/Neodragon", str(relative), revision=revision,
                                    local_dir=root, token=False, force_download=target.exists()))
        if result.resolve() != target.resolve() or not verify(target, entry):
            raise ValueError(f"Hub size or SHA-256 mismatch: {relative}")
        print(f"Verified {relative}", flush=True)
        return
    partial = target.with_name(target.name + ".partial")
    print(f"Fetching {relative} ({entry['bytes']:,} bytes)", flush=True)
    command = ["/usr/bin/curl", "--fail", "--location", "--show-error", "--silent",
               "--retry", "3", "--connect-timeout", "30", "--max-time", "3600",
               "--continue-at", "-", "--output", str(partial), entry["url"]]
    result = subprocess.run(command)
    if result.returncode == 33:  # server refuses Range: restart only this temporary file
        partial.unlink(missing_ok=True)
        subprocess.run(command, check=True)
    elif result.returncode:
        raise subprocess.CalledProcessError(result.returncode, command)
    if not verify(partial, entry):
        partial.unlink(missing_ok=True)
        raise ValueError(f"Size or SHA-256 mismatch: {relative}")
    partial.replace(target)
    print(f"Verified {relative}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path(".model-cache/neodragon-source"))
    parser.add_argument("--component", action="append", help="Fetch only a named component; may be repeated")
    parser.add_argument("--transport", choices=["curl", "hub"], default="curl")
    args = parser.parse_args()
    lock = json.loads(Path(__file__).with_name("source-lock.json").read_text())
    selected = set(args.component or [])
    known = {entry["path"].split("/")[0] for entry in lock["files"]}
    if selected - known:
        parser.error("Unknown components: " + ", ".join(sorted(selected - known)))
    for entry in lock["files"]:
        if not selected or entry["path"].split("/")[0] in selected:
            fetch(entry, args.destination, lock["weightsRevision"], args.transport)


if __name__ == "__main__":
    main()

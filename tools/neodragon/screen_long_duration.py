#!/usr/bin/env python3
"""Export nine-second attention ranges without overwriting two-second models."""
import argparse
import gc
import json
from pathlib import Path
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", type=Path, default=Path("build/Neodragon"))
parser.add_argument("--wait-for-baseline", action="store_true")
args = parser.parse_args()
for block in range(18):
    original = args.root / f"dit-block{block}-mixed-v1" / "report.json"
    while not original.exists() and args.wait_for_baseline:
        print(f"Waiting for two-second block {block} reference screen", flush=True)
        time.sleep(30)
    if not original.exists() or json.loads(original.read_text())["status"] != "passed-component-parity":
        raise SystemExit(f"Two-second block {block} did not pass")

from convert_transformer_block import main

for block in range(18):
    destination = args.root / f"dit-block{block}-9s-mixed-v1"
    report = destination / "report.json"
    if report.exists():
        saved = json.loads(report.read_text())
        if saved["status"] != "passed-component-parity" or saved["maximumSeconds"] != 9:
            raise SystemExit(f"Existing long-duration output failed: {destination}")
        print(f"Block {block}: existing nine-second check passed", flush=True)
        continue
    print(f"Exporting and checking nine-second block {block}", flush=True)
    sys.argv = ["convert_transformer_block.py", "--block", str(block), "--precision", "mixed",
                "--maximum-seconds", "9", "--boundary-only", "--output", str(destination)]
    result = main()
    gc.collect()
    if result:
        raise SystemExit(result)
    print(f"Block {block}: nine-second boundary parity passed", flush=True)

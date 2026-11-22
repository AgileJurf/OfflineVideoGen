#!/usr/bin/env python3
"""Summarize a completed local NativeCheck run without publishing its media.

Timings from an Intel Mac CPU functional check are not iPhone measurements or
evidence of a performance improvement. Raw journals and videos remain local.
"""
import argparse
import hashlib
import json
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--inspection", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--executable-record", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new evidence file; preserve earlier reports")
    journal = args.run / "generation.jsonl"
    events = [json.loads(line) for line in journal.read_text().splitlines()]
    metrics = json.loads((args.run / "metrics.json").read_text())
    inspection = json.loads(args.inspection.read_text())
    manifest = json.loads(args.manifest.read_text())
    executable = json.loads(args.executable_record.read_text())
    metadata = events[0]["fields"]
    seconds = int(metadata["durationSeconds"])
    video = args.run / "sailboat-seed42.mp4"
    assert events[0]["event"] == "started" and events[-1]["event"] == "finished"
    harness_status = events[-1]["fields"]["status"]
    revalidation = None
    if harness_status != "completed":
        # Preserve the original failed test record. A corrected export check may
        # validate the same MP4 after the engine itself completed successfully.
        assert harness_status == "failed" and events[-1]["fields"].get("error") == "invalidTensor"
        assert len([e for e in events if e["event"] == "neodragon_generation_completed"]) == 1
        revalidation = json.loads((args.run / "export-revalidation.json").read_text())
        assert revalidation["status"] == "passed-decoded-export-check"
        assert revalidation["videoSHA256"] == sha256(video)
        assert revalidation["decodedFrames"] == seconds * 24
    assert metrics["environment"] == "macos-cpu"
    assert metadata["hardware"] == "x86_64"
    assert metrics["modelRevision"] == manifest["weightsRevision"]
    assert executable["modelManifestSHA256"] == sha256(args.manifest)
    assert inspection["decodedFrames"] == seconds * 24
    assert inspection["width"] == 512 and inspection["height"] == 320
    assert abs(inspection["framesPerSecond"] - 24) < 0.01
    assert abs(inspection["durationSeconds"] - seconds) < 1 / 24
    assert not [e for e in events if e["event"] == "failure"]
    expected = set(metadata["expectedPartitions"].split(","))
    partitions = {}
    requested_units = set()
    for event in events:
        name, phase = event.get("partition"), event.get("phase")
        if name not in expected or phase not in ("load", "predict"):
            continue
        row = partitions.setdefault(name, {"name": name, "loadSeconds": 0.0,
            "predictionSeconds": 0.0, "loadCalls": 0, "predictionCalls": 0, "retainedModelHits": 0,
            "peakSampledFootprintDuringOperationBytes": 0})
        row["peakSampledFootprintDuringOperationBytes"] = max(row["peakSampledFootprintDuringOperationBytes"],
            event.get("snapshot", {}).get("footprintBytes", 0))
        if event["event"] == "begin":
            fields = event.get("fields", {})
            if "requestedComputeUnits" in fields:
                requested_units.add(fields["requestedComputeUnits"])
            if phase == "load" and fields.get("retainedModelHit") == "true":
                row["retainedModelHits"] += 1
        if event["event"] != "end":
            continue
        prefix = "load" if phase == "load" else "prediction"
        row[prefix + "Seconds"] += event["durationSeconds"]
        row[prefix + "Calls"] += 1
    assert set(partitions) == expected
    assert all(row["predictionCalls"] > 0 for row in partitions.values())
    snapshots = [e["snapshot"] for e in events if "snapshot" in e]
    cpu = snapshots[-1]["processCPUSeconds"] - snapshots[0]["processCPUSeconds"]
    wall = events[-1]["elapsedSeconds"] - events[0]["elapsedSeconds"]
    processors = int(metadata["logicalProcessorCount"])
    report = {
        "scope": "Complete native macOS CPU Release functional test; concurrent development work; not an iPhone benchmark or a controlled speed comparison",
        "status": "passed-native-macos-generation-and-export" if revalidation is None else "passed-native-macos-generation-with-export-revalidation",
        "deviceValidated": False,
        "nineSecondVideoValidatedOnThisHost": seconds == 9,
        "generationDurationSeconds": seconds,
        "environment": metrics["environment"],
        "hardware": metadata["hardware"], "osVersion": metadata["osVersion"],
        "rawJournalEnvironment": metadata["executionEnvironment"],
        "journalEnvironmentNote": "This executable predates the macOS journal-label fix. Its explicit test scope, hardware, OS and final metrics identify macOS CPU execution; the raw physical-device field is incorrect." if metadata["executionEnvironment"] == "physical-device" else "macOS host; not a physical iPhone",
        "originalHarnessStatus": harness_status,
        "exportRevalidation": revalidation,
        "exportValidationNote": "The original compressed-buffer counter saw 52 buffers containing 48 samples, including four empty marker buffers. Both independent inspection and the corrected harness decoded the same file as 48 frames. The original failed journal is retained." if revalidation is not None else "Decoded-frame check passed during the complete run",
        "modelVersion": manifest["modelVersion"], "modelRevision": manifest["weightsRevision"],
        "manifestSHA256": sha256(args.manifest), "executableSHA256": executable["executableSHA256"],
        "journalSHA256": sha256(journal), "metricsSHA256": sha256(args.run / "metrics.json"),
        "videoSHA256": sha256(video), "videoBytes": video.stat().st_size,
        "seed": int(metadata["seed"]),
        "prompt": "A small sailboat glides across a calm lake at sunrise.",
        "randomGenerator": "SplitMix64-BoxMuller-v1; not PyTorch seed-equivalent",
        "metrics": metrics,
        "processCPUSeconds": cpu,
        "averageProcessCPUPercentOneCoreIs100": cpu / wall * 100,
        "averageProcessCPUPercentAcrossLogicalProcessors": cpu / wall / processors * 100,
        "cpuSemantics": metadata["cpuSemantics"],
        "gpuUtilization": "Not measured; CPU-only execution requested",
        "requestedComputeUnits": sorted(requested_units),
        "peakSampledFootprintBytes": max(s.get("footprintBytes", 0) for s in snapshots),
        "processLifetimePeakBytes": max(s.get("processLifetimePeakBytes", 0) for s in snapshots),
        "memorySemantics": metadata["memorySemantics"],
        "sampleIntervalSeconds": float(metadata["sampleIntervalSeconds"]),
        "thermalStates": sorted({s["thermalState"] for s in snapshots}),
        "expectedPartitions": len(expected), "executedPartitions": len(partitions),
        "partitions": [partitions[name] for name in sorted(partitions)],
        "exportInspection": inspection,
        "perceptualQuality": "Not scored; inspect the local video and sampled frames separately. Unique frame hashes do not establish coherent motion or prompt adherence.",
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "partitions": len(partitions),
        "frames": inspection["decodedFrames"], "videoSHA256": report["videoSHA256"]}))


if __name__ == "__main__":
    main()

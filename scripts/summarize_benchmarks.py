#!/usr/bin/env python3
"""Summarize exported Local Frames JSONL logs without inventing missing measurements."""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from statistics import median


def read_events(path):
    events, problems = [], []
    for number, line in enumerate(path.read_text().splitlines(), 1):
        try:
            event = json.loads(line)
            if event.get("schemaVersion") != 1:
                raise ValueError("unsupported schema")
            if event.get("sequence") != len(events):
                problems.append(f"Sequence discontinuity at line {number}; timing coverage may be incomplete.")
            events.append(event)
        except (ValueError, TypeError) as error:
            problems.append(f"Unreadable line {number}: {error}. The log is incomplete.")
    return events, problems


def percentile(values, percentile):
    if not values:
        return None
    values = sorted(values)
    position = (len(values) - 1) * percentile
    low = int(position)
    return values[low] + (values[min(low + 1, len(values) - 1)] - values[low]) * (position - low)


def number(value, digits=3):
    return "Not measured" if value is None else f"{value:.{digits}f}"


def mib(value):
    return number(value / 1048576, 1) if value is not None else "Not measured"


def escape(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def summarize(path):
    events, problems = read_events(path)
    if not events:
        return {"path": path, "events": [], "problems": problems + ["No readable events."]}
    metadata = next((x.get("fields", {}) for x in events if x.get("event") == "started"), {})
    finish = next((x for x in reversed(events) if x.get("event") == "finished"), None)
    outcome = finish.get("fields", {}).get("status", "unknown") if finish else "INCOMPLETE — no terminal event"
    required = metadata.get("expectedPartitions", "").split(",")
    required = [name for name in required if name]
    successful_predictions = {x.get("partition") for x in events if x.get("event") == "end" and x.get("phase") == "predict"}
    snapshots = [x.get("snapshot", {}) for x in events]
    footprints = [x["footprintBytes"] for x in snapshots if x.get("footprintBytes") is not None]
    lifetime_peaks = [x["processLifetimePeakBytes"] for x in snapshots if x.get("processLifetimePeakBytes") is not None]
    available_memory = [x["availableProcessMemoryBytes"] for x in snapshots if x.get("availableProcessMemoryBytes") is not None]
    pending = {}
    for event in events:
        key = (event.get("partition"), event.get("phase"))
        if event.get("event") == "begin":
            pending[key] = event
        elif event.get("event") in ("end", "failure"):
            pending.pop(key, None)
    cpu_samples = [(x["elapsedSeconds"], x["snapshot"]["processCPUSeconds"]) for x in events
                   if x.get("snapshot", {}).get("processCPUSeconds") is not None]
    cpu = None
    if len(cpu_samples) >= 2 and cpu_samples[-1][0] > cpu_samples[0][0]:
        cpu = 100 * (cpu_samples[-1][1] - cpu_samples[0][1]) / (cpu_samples[-1][0] - cpu_samples[0][0])
    artifact_valid = False
    if finish and finish.get("fields", {}).get("videoFile"):
        name = finish["fields"]["videoFile"]
        if Path(name).name != name:
            problems.append("Video path is not a plain filename; verification refused.")
        else:
            video = path.parent / name
            if video.exists():
                with video.open("rb") as stream:
                    digest = hashlib.sha256()
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
                    actual = digest.hexdigest()
                artifact_valid = actual == finish["fields"].get("videoSHA256")
                if not artifact_valid:
                    problems.append("Exported video checksum does not match the log.")
            else:
                problems.append("The completed video was not provided; its checksum cannot be verified.")
    return dict(path=path, events=events, problems=problems, metadata=metadata, finish=finish,
                outcome=outcome, required=required, covered=successful_predictions,
                peak=max(footprints, default=None), lifetime_peak=max(lifetime_peaks, default=None),
                available_min=min(available_memory, default=None),
                pending=list(pending.values()),
                memory_warnings=[x for x in events if x.get("event") == "memory_warning"],
                cpu=cpu, artifact_valid=artifact_valid)


def render(runs):
    lines = ["# Local Frames device benchmark report", "",
             "This report describes supplied measurements only. Incomplete or simulator runs do not establish physical-device feasibility.", "",
             "GPU utilization and observed Neural Engine placement require an Instruments trace. Compute-plan records are estimates. Memory samples can miss short-lived peaks; the OS lifetime high-water mark includes earlier activity in the same process. CPU percentages use process CPU time, can exceed 100% across cores, and exclude separate Core ML service processes. All timings include instrumentation effects.", ""]
    for run in runs:
        lines += [f"## {run['path'].name}", ""]
        if not run["events"]:
            lines += run["problems"] + [""]
            continue
        meta, events = run["metadata"], run["events"]
        lines += ["| Field | Observed value |", "| --- | --- |"]
        for key in ["kind", "startedAt", "executionEnvironment", "hardware", "os", "appVersion", "appBuild", "sourceRevision", "modelRevision", "manifestSHA256", "configuration", "memoryLimitRequest", "prompt", "seed", "schedule", "cacheCondition", "sampleIntervalSeconds", "baselineJobID", "resumedFromJournal", "checkpointPolicy"]:
            if key in meta:
                lines.append(f"| {key} | {escape(meta[key])} |")
        lines += [f"| Outcome | {escape(run['outcome'])} |",
                  f"| Observed log span (seconds) | {number(events[-1].get('elapsedSeconds'))} |",
                  f"| Sampled process footprint maximum (MiB) | {mib(run['peak'])} |",
                  f"| Process-lifetime footprint high-water mark (MiB) | {mib(run['lifetime_peak'])} |",
                  f"| Lowest recorded available app memory (MiB, advisory) | {mib(run['available_min'])} |",
                  f"| Recorded memory warnings | {len(run['memory_warnings'])} |",
                  f"| Mean process CPU utilization (% of one core) | {number(run['cpu'], 1)} |",
                  f"| Thermal states | {', '.join(sorted({x.get('snapshot', {}).get('thermalState', 'unknown') for x in events}))} |",
                  "| GPU utilization | Not measured |", "| Actual Neural Engine execution | Not measured |", ""]
        for event in run["pending"]:
            lines += [f"Unfinished operation: **{escape(event.get('partition'))} / {escape(event.get('phase'))}**, begun at {number(event.get('elapsedSeconds'))} seconds. No completion or error event was recorded for it. This locates the interruption but does not establish the OS termination reason.", ""]
        if run["memory_warnings"]:
            lines += ["Recorded memory warnings:", ""]
            for warning in run["memory_warnings"]:
                lines += [f"- {number(warning.get('elapsedSeconds'))} seconds: {escape(warning.get('partition', 'unknown'))} / {escape(warning.get('phase', 'unknown'))}; process footprint {mib(warning.get('snapshot', {}).get('footprintBytes'))} MiB."]
            lines += [""]
        engine = next((x for x in events if x.get("event") == "engine_completed"), None)
        if engine:
            lines += [f"Engine session wall time: {engine.get('fields', {}).get('elapsedSeconds', 'unknown')} seconds. This includes cooling waits and checkpoint I/O, and excludes subsequent library persistence, artifact copying, and hashing.", ""]
        pauses = [x for x in events if x.get("event") == "pause_end"]
        if pauses:
            lines += [f"Recorded pause intervals: {len(pauses)}; total {number(sum(x.get('durationSeconds', 0) for x in pauses))} seconds. An unfinished pause may not be included.", ""]
        restored = next((x for x in events if x.get("event") == "checkpoint_restored"), None)
        if restored or meta.get("resumedFromJournal"):
            step = restored.get("fields", {}).get("completedSteps", "unknown") if restored else "unknown"
            lines += [f"**Resumed session**, with {escape(step)} motion steps previously saved. This session's time and partition coverage do not represent the complete generation. Keep the earlier journals with the same baselineJobID; do not report this segment as a full-generation speedup.", ""]
        background = [x for x in events if x.get("event") in ("background_requested", "background_granted", "background_unavailable", "background_expired", "scene_changed")]
        if background:
            lines += ["Background lifecycle evidence:", ""]
            lines += [f"- {number(x.get('elapsedSeconds'))} s: {escape(x['event'])}; {escape(x.get('fields', {}))}" for x in background]
            lines += ["", "A background grant is not proof of uninterrupted background completion; correlate scene events and completed model operations.", ""]
        if run["problems"]:
            lines += ["Evidence limitations:", ""] + [f"- {escape(x)}" for x in run["problems"]] + [""]
        if meta.get("kind") == "generation":
            missing = set(run["required"]) - run["covered"]
            lines += [f"Successful partition prediction coverage: **{len(set(run['required']) & run['covered'])}/{len(run['required'])}**.", "",
                      f"Exported video SHA-256 verified: **{'yes' if run['artifact_valid'] else 'no'}**. Visual quality, motion consistency, and prompt adherence require inspection of that actual video.", ""]
            if missing:
                lines += ["Unreached or unsuccessful partitions: " + ", ".join(sorted(missing)) + ".", ""]
        grouped = defaultdict(lambda: {"load": [], "predict": [], "compile": [], "sample_peaks": [], "failures": []})
        for event in events:
            name = event.get("partition")
            phase = event.get("phase")
            if not name:
                continue
            row = grouped[name]
            if event.get("event") == "end" and phase in ("load", "predict", "compile"):
                row[phase].append(event["durationSeconds"])
            footprint = event.get("snapshot", {}).get("footprintBytes")
            if footprint is not None and phase in ("load", "predict", "compile"):
                row["sample_peaks"].append(footprint)
            if event.get("event") == "failure":
                row["failures"].append(f"{phase}: {event.get('fields', {}).get('error', 'unknown error')}")
        if meta.get("kind") in ("generation", "installation"):
            lines += ["| Partition | Loads | Load total s | Load median s | Predictions | Predict total s | Predict median s | Predict p95 s | Compile total s | Active sampled footprint MiB |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
            for name in sorted(set(run["required"]) | set(grouped)):
                row = grouped[name]
                loads, predictions, compiles = row["load"], row["predict"], row["compile"]
                lines.append(f"| {name} | {len(loads)} | {number(sum(loads) if loads else None)} | {number(median(loads) if loads else None)} | {len(predictions)} | {number(sum(predictions) if predictions else None)} | {number(median(predictions) if predictions else None)} | {number(percentile(predictions, .95))} | {number(sum(compiles) if compiles else None)} | {mib(max(row['sample_peaks'], default=None))} |")
            lines += ["", "Footprint values describe the whole process while that partition was active, not exclusive per-partition allocations. Prediction percentiles combine different call shapes/stages; use the raw inputShapes and begin/end events to compare like-for-like calls.", ""]
            costs = sorted(((sum(v["load"]) + sum(v["predict"]), name) for name, v in grouped.items()), reverse=True)
            if costs and costs[0][0] > 0:
                lines += ["Largest observed combined load/predict totals:", ""] + [f"- {name}: {seconds:.3f} seconds." for seconds, name in costs[:5]] + [""]
        plan_counts = defaultdict(int)
        for event in events:
            if event.get("event") == "compute_plan_operation":
                fields = event.get("fields", {})
                plan_counts[(fields.get("requestedComputeUnits"), fields.get("preferredDevice"))] += 1
        if plan_counts:
            lines += ["Planner preferences (operation counts, not observed execution):", "", "| Requested configuration | Preferred device | Operations |", "| --- | --- | ---: |"]
            lines += [f"| {config} | {device} | {count} |" for (config, device), count in sorted(plan_counts.items())] + [""]
        failures = [(name, message) for name, row in grouped.items() for message in row["failures"]]
        if failures:
            lines += ["Observed failures:", ""] + [f"- **{name}**: {escape(message)}" for name, message in failures] + [""]
    lines += ["## Optimization decision", "",
              "No speedup or quality improvement is inferred from these logs alone. Before testing an optimization, require a completed physical iPhone baseline, successful predictions from every partition required by that model, a verified exported MP4, and visual review. Compare matched prompts/seeds, device/OS, model hashes, thermal/cache conditions, and instrumentation. Separate first-run and repeated-run results.", "",
              "Float16 conversion, Neural Engine placement changes, and sampler/step reductions remain experimental until paired output and timing measurements pass. Preserve the baseline tag and model manifest. Choose the next experiment using the measured load/predict bottleneck table; missing measurements are not zero-cost operations.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    paths = []
    for path in args.inputs:
        paths += sorted(path.glob("*.jsonl")) if path.is_dir() else [path]
    if not paths:
        parser.error("No JSONL measurement logs were supplied.")
    args.output.write_text(render([summarize(path) for path in paths]))
    print(f"Wrote {args.output} from {len(paths)} supplied log(s).")


if __name__ == "__main__":
    main()

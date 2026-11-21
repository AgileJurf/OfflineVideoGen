import json
import tempfile
import unittest
from pathlib import Path

from summarize_benchmarks import render, summarize


class BenchmarkReportTests(unittest.TestCase):
    def test_memory_interruption_is_located_without_inventing_a_termination_reason(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "memory-interruption.jsonl"
            base = {"schemaVersion": 1, "fields": {}}
            events = [
                dict(base, sequence=0, elapsedSeconds=0, event="started", fields={"kind": "generation", "expectedPartitions": "block"}, snapshot={}),
                dict(base, sequence=1, elapsedSeconds=1, event="begin", partition="block", phase="load", snapshot={}),
                dict(base, sequence=2, elapsedSeconds=2, event="end", partition="block", phase="load", durationSeconds=1, snapshot={}),
                dict(base, sequence=3, elapsedSeconds=2, event="begin", partition="block", phase="predict", snapshot={"availableProcessMemoryBytes": 3000000}),
                dict(base, sequence=4, elapsedSeconds=3, event="memory_warning", partition="block", phase="predict", snapshot={"footprintBytes": 3000000000, "availableProcessMemoryBytes": 1000000})
            ]
            path.write_text("\n".join(json.dumps(x) for x in events))
            result = summarize(path)
            self.assertEqual(len(result["pending"]), 1)
            self.assertEqual(result["pending"][0]["phase"], "predict")
            self.assertEqual(result["available_min"], 1000000)
            self.assertEqual(len(result["memory_warnings"]), 1)
            self.assertFalse(result["artifact_valid"])
            report = render([result])
            self.assertIn("Unfinished operation: **block / predict**", report)
            self.assertIn("does not establish the OS termination reason", report)
            self.assertIn("**0/1**", report)

    def test_partial_log_cannot_become_a_success(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "interrupted.jsonl"
            path.write_text(json.dumps({"schemaVersion": 1, "sequence": 0, "elapsedSeconds": 0,
                "event": "started", "fields": {"kind": "generation", "expectedPartitions": "a,b", "executionEnvironment": "synthetic-test-fixture"},
                "snapshot": {}}) + '\n{"truncated":')
            result = summarize(path)
            self.assertIn("INCOMPLETE", result["outcome"])
            self.assertFalse(result["artifact_valid"])
            report = render([result])
            self.assertIn("**0/2**", report)
            self.assertIn("Not measured", report)
            self.assertIn("Unreadable line", report)

    def test_cpu_accounting_and_failed_partition_are_reported_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "failed.jsonl"
            base = {"schemaVersion": 1, "fields": {}}
            events = [
                dict(base, sequence=0, elapsedSeconds=0, event="started", fields={"kind": "generation", "expectedPartitions": "a,b"}, snapshot={"processCPUSeconds": 1, "footprintBytes": 100}),
                dict(base, sequence=1, elapsedSeconds=1, event="begin", phase="load", partition="a", snapshot={}),
                dict(base, sequence=2, elapsedSeconds=2, event="failure", phase="load", partition="a", durationSeconds=1, fields={"error": "fixture failure"}, snapshot={}),
                dict(base, sequence=3, elapsedSeconds=3, event="finished", fields={"status": "failed"}, snapshot={"processCPUSeconds": 7, "footprintBytes": 200})
            ]
            path.write_text("\n".join(json.dumps(x) for x in events))
            result = summarize(path)
            self.assertEqual(result["cpu"], 200)
            self.assertEqual(result["peak"], 200)
            self.assertEqual(result["covered"], set())
            report = render([result])
            self.assertIn("load: fixture failure", report)
            self.assertIn("GPU utilization | Not measured", report)

    def test_artifact_path_cannot_escape_export_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "unsafe.jsonl"
            events = [dict(schemaVersion=1, sequence=0, elapsedSeconds=0, event="started", fields={}, snapshot={}),
                      dict(schemaVersion=1, sequence=1, elapsedSeconds=1, event="finished", fields={"status": "succeeded", "videoFile": "../outside.mp4"}, snapshot={})]
            path.write_text("\n".join(json.dumps(x) for x in events))
            result = summarize(path)
            self.assertFalse(result["artifact_valid"])
            self.assertIn("verification refused", result["problems"][0])


if __name__ == "__main__":
    unittest.main()

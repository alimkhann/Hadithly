#!/usr/bin/env python3
"""Capture aggregate usage through the installed read-only Convex CLI."""

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--log-sample-seconds", type=int, default=0)
    parser.add_argument("--log-history", type=int, default=0)
    args = parser.parse_args()
    if not 0 <= args.log_sample_seconds <= 45 or not 0 <= args.log_history <= 2000:
        parser.error("Log sample must be 0-45 seconds and history 0-2000 events")
    backend = Path(__file__).resolve().parents[1] / "backend"
    command = [
        str(backend / "node_modules/.bin/convex"),
        "deployment", "usage", "--deployment", args.deployment, "--json",
    ]
    started = datetime.now(timezone.utc).isoformat()
    try:
        result = subprocess.run(
            command, cwd=backend, stdin=subprocess.DEVNULL,
            capture_output=True, text=True, timeout=45,
        )
        if result.returncode:
            raise ValueError(f"Convex usage command failed with exit {result.returncode}")
        raw = json.loads(result.stdout)
        seed_status = raw["seedStatus"]
        if seed_status not in {"complete", "pending", "partial"}:
            raise ValueError("Unrecognized usage backfill status")
        metrics = {}
        for name in (
            "functionCalls", "databaseIoGb", "dataEgressGb", "searchQueryGb",
            "actionComputeConvexGbHours", "actionComputeNodeJsGbHours",
            "actionComputeCpuGbHours", "queryMutationComputeGbHours",
            "aiGatewayCostDollars",
        ):
            if name not in raw["metrics"]:
                continue
            metric = raw["metrics"][name]
            if metric["unit"] not in {"calls", "GB", "GB-hours", "Query-GB", "dollars"}:
                raise ValueError(f"Unrecognized unit for {name}")
            usage = {key: metric["usage"][key] for key in ("current_day", "current_month")}
            if any(type(value) not in (float, int) or not math.isfinite(value) or value < 0
                   for value in usage.values()):
                raise ValueError(f"Invalid usage for {name}")
            metrics[name] = {"unit": metric["unit"], "usage": usage}
        if "functionCalls" not in metrics or "databaseIoGb" not in metrics:
            raise ValueError("Required usage dimensions are missing")
    except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError):
        parser.exit(1, "Could not capture validated usage; no output written. Check CLI access and response schema.\n")
    output = {
        "deployment": args.deployment,
        "scope": "live deployment aggregate, not a reader journey or team allowance",
        "startedAtUtc": started,
        "completedAtUtc": datetime.now(timezone.utc).isoformat(),
        "seedStatus": seed_status,
        "metrics": metrics,
    }
    if args.log_sample_seconds:
        log_command = command[:1] + ["logs", "--deployment", args.deployment,
                                    "--history", str(args.log_history), "--jsonl"]
        child = subprocess.Popen(log_command, cwd=backend, stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            stdout, _ = child.communicate(timeout=args.log_sample_seconds)
        except subprocess.TimeoutExpired:
            child.terminate()
            try:
                stdout, _ = child.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                stdout, _ = child.communicate()
        if child.returncode not in (0, -15, -9):
            parser.exit(1, "Could not sample execution logs; no output written.\n")
        summaries = {}
        timestamps = []
        for line in stdout.splitlines():
            try:
                event = json.loads(line)
                name = event["identifier"]
                if event.get("kind") != "Completion" or not re.fullmatch(r"[A-Za-z0-9_./:-]+", name):
                    continue
                timestamp = event["timestamp"]
                if type(timestamp) not in (int, float) or not math.isfinite(timestamp):
                    continue
                usage_stats = event.get("usageStats")
                if not isinstance(usage_stats, dict):
                    usage_stats = {}
                row = summaries.setdefault(name, {"completionEvents": 0, "cachedResultEvents": 0,
                    "databaseIoReadBytes": 0, "databaseIoWriteBytes": 0, "networkEgressBytes": 0})
                row["completionEvents"] += 1
                row["cachedResultEvents"] += event.get("cachedResult") is True
                for key in ("databaseIoReadBytes", "databaseIoWriteBytes", "networkEgressBytes"):
                    number = usage_stats.get(key)
                    if type(number) in (int, float) and math.isfinite(number) and number >= 0:
                        if row[key] is not None:
                            row[key] += number
                    else:
                        row[key] = None
                timestamps.append(timestamp)
            except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
                continue
        output["sampledExecutionLogs"] = {
            "scope": "ambient logs including requested history; not a controlled idle or native workload",
            "captureSeconds": args.log_sample_seconds, "requestedHistoryEvents": args.log_history,
            "firstEventUtc": datetime.fromtimestamp(min(timestamps), timezone.utc).isoformat() if timestamps else None,
            "lastEventUtc": datetime.fromtimestamp(max(timestamps), timezone.utc).isoformat() if timestamps else None,
            "functions": summaries,
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(f"Captured {len(metrics)} aggregate metrics; seedStatus={seed_status}")


if __name__ == "__main__":
    main()

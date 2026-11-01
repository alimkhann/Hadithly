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
    parser.add_argument("--since", help="Inclusive UTC execution-window start")
    parser.add_argument("--until", help="Exclusive UTC execution-window end")
    args = parser.parse_args()
    window = None
    if args.since or args.until:
        try:
            first = datetime.fromisoformat(args.since.replace("Z", "+00:00"))
            last = datetime.fromisoformat(args.until.replace("Z", "+00:00"))
            if first.utcoffset() is None or last.utcoffset() is None or first >= last or not args.log_sample_seconds:
                raise ValueError()
            window = (first.timestamp(), last.timestamp())
        except (AttributeError, ValueError):
            parser.error("Execution window needs ordered timezone-aware --since/--until and a log sample")
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
        available_timestamps = []
        for line in stdout.splitlines():
            try:
                event = json.loads(line)
                name = event["identifier"]
                if event.get("kind") != "Completion" or not re.fullmatch(r"[A-Za-z0-9_./:-]+", name):
                    continue
                timestamp = event["timestamp"]
                if type(timestamp) not in (int, float) or not math.isfinite(timestamp):
                    continue
                available_timestamps.append(timestamp)
                if window and not window[0] <= timestamp < window[1]:
                    continue
                usage_stats = event.get("usageStats")
                if not isinstance(usage_stats, dict):
                    usage_stats = {}
                row = summaries.setdefault(name, {"completionEvents": 0, "cachedResultEvents": 0,
                    "databaseIoReadBytes": 0, "databaseIoWriteBytes": 0, "networkEgressBytes": 0,
                    "executionSeconds": 0, "failedEvents": 0, "databaseReadDocuments": 0,
                    "databaseWriteDocuments": 0, "databaseWriteIndexRows": 0,
                    "actionMemoryGbHours": 0 if event.get("udfType") == "Action" else None})
                row["completionEvents"] += 1
                row["cachedResultEvents"] += event.get("cachedResult") is True
                row["failedEvents"] += bool(event.get("error"))
                execution = event.get("executionTime")
                if type(execution) in (int, float) and math.isfinite(execution) and execution >= 0:
                    if row["executionSeconds"] is not None:
                        row["executionSeconds"] += execution
                else:
                    row["executionSeconds"] = None
                if event.get("udfType") == "Action":
                    memory = usage_stats.get("memoryUsedMb")
                    if (type(memory) in (int, float) and math.isfinite(memory) and memory >= 0
                            and type(execution) in (int, float) and math.isfinite(execution) and execution >= 0):
                        if row["actionMemoryGbHours"] is not None:
                            row["actionMemoryGbHours"] += memory * execution / (1024 * 3600)
                    else:
                        row["actionMemoryGbHours"] = None
                for key in ("databaseIoReadBytes", "databaseIoWriteBytes", "networkEgressBytes",
                            "databaseReadDocuments", "databaseWriteDocuments", "databaseWriteIndexRows"):
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
            "scope": "execution completions within requested UTC window; attribution needs workload evidence" if window else "ambient logs including requested history; not a controlled idle or native workload",
            "requestedWindow": {"sinceUtc": args.since, "untilUtc": args.until} if window else None,
            "historyReachesWindowStart": min(available_timestamps) <= window[0] if window and available_timestamps else None,
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

#!/usr/bin/env python3
"""Observe scheduled push completions without invoking functions or retaining payloads."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deployment", required=True)
    parser.add_argument("--since", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=2)
    args = parser.parse_args()
    since = datetime.fromisoformat(args.since.replace("Z", "+00:00")).timestamp()
    if args.runs not in (1, 2):
        parser.error("Observe one or two runs")
    backend = Path(__file__).resolve().parents[1] / "backend"
    command = [str(backend / "node_modules/.bin/convex"), "logs", "--deployment",
               args.deployment, "--history", "2000", "--jsonl"]
    child = subprocess.Popen(command, cwd=backend, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    events = {}
    roots = {}
    accepted = {}
    buffer = b""
    deadline = time.monotonic() + 2100

    def interrupt(_signal, _frame):
        raise KeyboardInterrupt

    previous = signal.signal(signal.SIGTERM, interrupt)
    try:
        while time.monotonic() < deadline and len(accepted) < args.runs:
            if child.poll() is not None:
                raise RuntimeError("Read-only log stream stopped; raw output withheld")
            for key, _ in selector.select(timeout=1):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    continue
                buffer += data
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    try:
                        event = json.loads(line)
                        if event.get("kind") != "Completion" or event["timestamp"] < since:
                            continue
                        if event["identifier"] not in {"actions/daily:sendDueDailyPushes",
                                                        "library:listPushDeliveryPage", "library:listBucketPage"}:
                            continue
                        identity = event["executionId"]
                        metadata = {name: event.get(name) for name in
                                    ("identifier", "timestamp", "parentExecutionId", "executionTime", "caller")}
                        metadata["error"] = bool(event.get("error"))
                        metadata["usage"] = event.get("usageStats", {})
                        events[identity] = metadata
                        if metadata["identifier"] == "actions/daily:sendDueDailyPushes":
                            roots[identity] = metadata
                    except (ValueError, TypeError, KeyError, AttributeError):
                        continue
            for identity, root in roots.items():
                if identity in accepted:
                    continue
                pages = [e for e in events.values() if e["parentExecutionId"] == identity]
                if not pages:
                    continue
                old = sum(e["identifier"] == "library:listBucketPage" for e in pages)
                new = sum(e["identifier"] == "library:listPushDeliveryPage" for e in pages)
                if root["error"] or old or not new:
                    raise RuntimeError("Unexpected dispatch execution; inspect allowlisted live evidence")
                row = {"completedAtUtc": datetime.fromtimestamp(root["timestamp"], timezone.utc).isoformat(),
                       "newTokenPageQueries": new, "oldBucketQueries": old,
                       "actionExecutionSeconds": root["executionTime"],
                       "schedulerCallerRecognized": root["caller"] in {"Cron", "cron", "CronJob", "cronJob", "Scheduled"},
                       "actionNetworkEgressBytes": root["usage"].get("networkEgressBytes"),
                       "tokenDatabaseIoReadBytes": sum(e["usage"].get("databaseIoReadBytes", 0) for e in pages),
                       "success": True}
                accepted[identity] = row
                print(f"Observed dispatch completion: {new} token page query, no old bucket calls", flush=True)
        if len(accepted) < args.runs:
            raise RuntimeError("Observation timed out before complete correlated runs")
        result = {"deployment": args.deployment, "sinceUtc": args.since,
                  "scope": "passive deployed execution logs, no manual dispatch or provider activation",
                  "runs": list(accepted.values())}
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    finally:
        signal.signal(signal.SIGTERM, previous)
        selector.close()
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


if __name__ == "__main__":
    main()

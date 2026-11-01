#!/usr/bin/env python3
"""Summarize measured Android scrolling frames and validate workload movement."""
import argparse
import json
from pathlib import Path
import statistics


def android_metrics(path):
    data = json.loads(path.read_text())
    frames = data["frames"]
    if len(frames) < 10 or data["arabicTopAfter"] >= data["arabicTopBefore"] - 100:
        raise ValueError("The Android workload has insufficient frames or did not scroll")
    ordered = sorted(frame[0] / 1e6 for frame in frames)
    supported = [frame for frame in frames if frame[1] > 0]
    return {
        "frames": len(frames),
        "median_ms": statistics.median(ordered),
        "p95_ms": ordered[min(len(ordered) - 1, int(len(ordered) * .95))],
        "max_ms": max(ordered),
        "frames_with_deadline": len(supported),
        "frames_at_or_over_deadline": sum(frame[0] >= frame[1] for frame in supported),
        "dropped_reports": data["droppedReports"],
        "page_requests": data["pageRequests"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-json", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps({"android": android_metrics(args.android_json)}, indent=2))


if __name__ == "__main__":
    main()

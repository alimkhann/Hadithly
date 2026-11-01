#!/usr/bin/env python3
"""Validate native scrolling measurements against explicit workload budgets."""
import argparse
import json
import math
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


def ios_metrics(path, region="Scroll_DraggingAndDeceleration"):
    data = json.loads(path.read_text())
    ratio = data[f"Hitch Time Ratio ({region}), ms per s"]
    duration = data[f"Duration ({region}), s"]
    cpu = data["CPU Time (app), s"]
    if len(ratio) < 3 or len(cpu) != len(ratio) or len(duration) != len(ratio):
        raise ValueError("Require at least three complete physical scrolling samples")
    if not all(math.isfinite(v) and v >= 0 for values in [ratio, duration, cpu] for v in values) or min(duration) <= 0:
        raise ValueError("Invalid or empty scrolling measurement")
    if region == "ReaderActiveScroll":
        frames = data.get(f"Frame Count ({region}), frames", [])
        if len(frames) != len(ratio) or not all(math.isfinite(v) and v > 0 and int(v) == v for v in frames):
            raise ValueError("Native-scroll acceptance requires valid positive frame counts in every run")
    return {
        "region": region,
        "active_seconds": duration,
        "scroll_hitch_ms_per_second": {"samples": ratio, "mean": statistics.mean(ratio), "worst": max(ratio)},
        "cpu_seconds": {"samples": cpu, "mean": statistics.mean(cpu)},
        "note": "Named scroll-signpost metrics only. App-wide zero fields and hardware maximum refresh are not used as proof.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--android-json", type=Path)
    inputs.add_argument("--ios-json", type=Path)
    parser.add_argument("--max-scroll-hitch-ms-per-second", type=float)
    parser.add_argument("--max-cpu-seconds", type=float)
    parser.add_argument("--each-scroll-hitch-below", type=float,
                        help="Every retained run must be strictly below this ratio")
    parser.add_argument("--scroll-region", choices=["Scroll_DraggingAndDeceleration", "ReaderActiveScroll"],
                        default="Scroll_DraggingAndDeceleration")
    args = parser.parse_args()
    budgets = [v for v in [args.max_scroll_hitch_ms_per_second, args.max_cpu_seconds, args.each_scroll_hitch_below] if v is not None]
    if budgets and (not args.ios_json or not all(math.isfinite(v) and v > 0 for v in budgets)):
        parser.error("Positive finite physical iOS budgets require --ios-json")
    if args.android_json:
        print(json.dumps({"android": android_metrics(args.android_json)}, indent=2))
        return 0
    result = ios_metrics(args.ios_json, args.scroll_region)
    passed = ((args.max_scroll_hitch_ms_per_second is None or result["scroll_hitch_ms_per_second"]["mean"] <= args.max_scroll_hitch_ms_per_second)
              and (args.max_cpu_seconds is None or result["cpu_seconds"]["mean"] <= args.max_cpu_seconds)
              and (args.each_scroll_hitch_below is None or result["scroll_hitch_ms_per_second"]["worst"] < args.each_scroll_hitch_below))
    result["budget_passed"] = passed if budgets else None
    print(json.dumps({"ios": result}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

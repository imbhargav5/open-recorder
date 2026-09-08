"""Run opt-in native export benchmarks. Output contains local fixture paths: do not upload it."""
import argparse
import json
import os
import platform
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("manifest", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--configuration", choices=["debug", "release"], default="release")
parser.add_argument("--diagnostics", action="store_true")
parser.add_argument("--capture-frames", action="store_true")
args = parser.parse_args()
if (args.output / "results.json").exists():
    parser.error("Choose a fresh output directory; existing results must not be mixed with a new run")
root = Path(__file__).resolve().parent.parent
modified = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip())
hardware = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
environment = {**os.environ, "OPEN_RECORDER_EXPORT_BENCH_MANIFEST": str(args.manifest.resolve()),
               "OPEN_RECORDER_EXPORT_BENCH_OUTPUT": str(args.output.resolve()),
               "OPEN_RECORDER_EXPORT_REVISION": revision,
               "OPEN_RECORDER_EXPORT_DIAGNOSTICS": "1" if args.diagnostics else "0",
               "OPEN_RECORDER_EXPORT_CAPTURE_FRAMES": "1" if args.capture_frames else "0"}
result = subprocess.run(["swift", "test", "--package-path", "apps/macos", "-c", args.configuration,
                         "-Xswiftc", "-DOPEN_RECORDER_TESTING", "--filter", "VideoExportBenchmarkTests"], env=environment, cwd=root)
report = args.output / "results.json"
if report.exists():
    rows = json.loads(report.read_text())
    for row in rows:
        row.update(hardware=hardware, operatingSystem=platform.mac_ver()[0], sourceModified=modified, captureFrames=args.capture_frames)
    report.write_text(json.dumps(rows, indent=2) + "\n")
    summary = []
    for name in dict.fromkeys(row["fixture"] for row in rows):
        measurements = [row for row in rows if row["fixture"] == name and not row["warmup"]]
        if measurements:
            summary.append({"fixture": name, "runs": len(measurements),
                            "exportMedianSeconds": statistics.median(row["exportSeconds"] for row in measurements),
                            "saveMedianSeconds": statistics.median(row["saveSeconds"] for row in measurements),
                            "peakResidentBytes": max(row["peakResidentBytes"] for row in measurements)})
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
raise SystemExit(result.returncode)

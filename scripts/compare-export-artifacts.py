"""Compare local benchmark exports and optional pre-encode captures (requires FFmpeg)."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def probe(path):
    result = subprocess.check_output([
        "ffprobe", "-v", "error", "-count_frames", "-show_streams", "-of", "json", str(path)], text=True)
    return json.loads(result)["streams"]


def rgba(path):
    return subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgba", "-"])


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("baseline", type=Path)
parser.add_argument("candidate", type=Path)
args = parser.parse_args()
results = []
for baseline in sorted(args.baseline.glob("*-1.mov")):
    candidate = args.candidate / baseline.name
    before, after = probe(baseline), probe(candidate)
    for kind in ["video", "audio"]:
        a = [s for s in before if s["codec_type"] == kind]
        b = [s for s in after if s["codec_type"] == kind]
        assert len(a) == len(b), f"{baseline.name}: {kind} track count changed"
        for x, y in zip(a, b):
            keys = ["codec_name", "width", "height", "pix_fmt", "color_range", "color_space", "color_transfer",
                    "color_primaries", "r_frame_rate", "nb_read_frames", "sample_rate", "channels"]
            for key in keys:
                assert x.get(key) == y.get(key), f"{baseline.name}: {key} changed"
            for key in ["start_time", "duration"]:
                assert abs(float(x.get(key, 0)) - float(y.get(key, 0))) <= 0.001, f"{baseline.name}: {kind} {key} changed"
    result = subprocess.run(["ffmpeg", "-v", "info", "-i", str(baseline), "-i", str(candidate),
                             "-lavfi", "[0:v][1:v]ssim", "-an", "-f", "null", "-"], capture_output=True, text=True, check=True)
    match = re.search(r"All:([0-9.]+)", result.stderr)
    assert match, result.stderr[-2000:]
    ssim = float(match.group(1))
    results.append({"file": baseline.name, "ssim": ssim})
    assert ssim >= 0.999, f"{baseline.name}: SSIM {ssim} < 0.999"

for baseline in sorted(args.baseline.glob("*-1-frames/*.png")):
    candidate = args.candidate / baseline.relative_to(args.baseline)
    before, after = rgba(baseline), rgba(candidate)
    assert len(before) == len(after), "Pre-encode dimensions changed"
    delta = max(abs(a - b) for a, b in zip(before, after))
    results.append({"frame": str(baseline.relative_to(args.baseline)), "maximumChannelDifference": delta})
    assert delta <= 2, f"{baseline}: pre-encode difference {delta} > 2"

assert results, "No matching benchmark artifacts found"
print(json.dumps(results, indent=2))

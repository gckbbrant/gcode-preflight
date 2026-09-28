#!/usr/bin/env python3
"""Generate or verify the README SVGs using the real MoonBit CLI."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "docs" / "images"
DEMOS = (
    ("valid", "Pass", "samples/valid.nc", "samples/profile-demo.json"),
    ("overlimit", "Fail", "samples/overlimit.nc", "samples/profile.json"),
    (
        "incomplete",
        "Incomplete",
        "samples/unsupported-demo.nc",
        "samples/profile-demo.json",
    ),
)


def render_one(name: str, status: str, program: str, profile: str, work: Path) -> bytes:
    svg_path = work / f"{name}.svg"
    report_path = work / f"{name}.json"
    command = [
        "moon",
        "run",
        "--target",
        "native",
        "cmd/main",
        "--",
        "check",
        str(ROOT / program),
        "--profile",
        str(ROOT / profile),
        "--svg",
        str(svg_path),
        "--json",
        str(report_path),
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    expected_exit = 0 if status == "Pass" else 1
    if result.returncode != expected_exit:
        raise RuntimeError(
            f"{name}: CLI returned {result.returncode}, expected {expected_exit}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report["status"] != status:
        raise RuntimeError(f"{name}: expected {status}, got {report['status']}")
    root = ET.parse(svg_path).getroot()
    if root.tag != "{http://www.w3.org/2000/svg}svg":
        raise RuntimeError(f"{name}: CLI output is not an SVG document")
    visible_text = "".join(root.itertext())
    if f"CNC G-code Preflight — {status.upper()}" not in visible_text:
        raise RuntimeError(f"{name}: SVG does not display its analysis status")
    status_class = f"status-{status.lower()}"
    status_label = root.find(
        f".//{{http://www.w3.org/2000/svg}}text[@class='{status_class}']"
    )
    if status_label is None or status.upper() not in "".join(status_label.itertext()):
        raise RuntimeError(f"{name}: SVG status is not visible in the report header")
    if f"{len(report['segments'])} moves" not in visible_text:
        raise RuntimeError(f"{name}: SVG omits its analyzed move count")
    if "X coordinate (mm)" not in visible_text or "Y coordinate (mm)" not in visible_text:
        raise RuntimeError(f"{name}: SVG omits its axes or units")
    return svg_path.read_bytes()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the checked-in SVGs differ from current CLI output",
    )
    args = parser.parse_args()
    IMAGES.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="gcode-preflight-renders-") as temp:
        work = Path(temp)
        for name, status, program, profile in DEMOS:
            rendered = render_one(name, status, program, profile, work)
            destination = IMAGES / f"{name}.svg"
            if args.check:
                if not destination.is_file():
                    raise RuntimeError(f"Missing {destination.relative_to(ROOT)}")
                if destination.read_bytes() != rendered:
                    raise RuntimeError(
                        f"{destination.relative_to(ROOT)} is stale; run "
                        "python scripts/generate_demo_renders.py"
                    )
            else:
                destination.write_bytes(rendered)
            print(f"PASS {name}: {status}, {destination.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

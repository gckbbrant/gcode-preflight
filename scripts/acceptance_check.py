#!/usr/bin/env python3
"""Run the project acceptance checks and collect a reviewer-ready evidence bundle."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEMOS = (
    ("pass", "Pass", "samples/valid.nc", "samples/profile-demo.json"),
    ("fail", "Fail", "samples/overlimit.nc", "samples/profile.json"),
    (
        "incomplete",
        "Incomplete",
        "samples/unsupported-demo.nc",
        "samples/profile-demo.json",
    ),
)


def run_command(
    name: str,
    command: list[str],
    log_path: Path,
    expected_exit: int = 0,
) -> dict:
    started = time.monotonic()
    try:
        process = subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        output = process.stdout
        returncode = process.returncode
        passed = returncode == expected_exit
    except OSError as error:
        output = f"Could not start command: {error}\n"
        returncode = None
        passed = False

    log_path.write_text(output, encoding="utf-8")
    result = {
        "name": name,
        "command": command,
        "expected_exit_code": expected_exit,
        "exit_code": returncode,
        "passed": passed,
        "duration_seconds": round(time.monotonic() - started, 3),
        "log": str(log_path.relative_to(ROOT)),
    }
    print(f"{'PASS' if passed else 'FAIL'} {name} ({result['duration_seconds']}s)")
    if not passed:
        print(output[-5000:])
    return result


def run_demo(name: str, status: str, program: str, profile: str, out: Path) -> dict:
    demo_dir = out / "demos"
    demo_dir.mkdir(parents=True, exist_ok=True)
    json_path = demo_dir / f"{name}.json"
    svg_path = demo_dir / f"{name}.svg"
    command = [
        "moon", "run", "--target", "native", "cmd/main", "--", "check",
        str(ROOT / program), "--profile", str(ROOT / profile),
        "--svg", str(svg_path), "--json", str(json_path),
    ]
    result = run_command(
        f"Demo {name.upper()}", command, out / f"demo-{name}.log",
        expected_exit=0 if status == "Pass" else 1,
    )
    try:
        report = json.loads(json_path.read_text(encoding="utf-8"))
        svg_root = ET.parse(svg_path).getroot()
        valid = report.get("status") == status and svg_root.tag == (
            "{http://www.w3.org/2000/svg}svg"
        )
        result["expected_report_status"] = status
        result["actual_report_status"] = report.get("status")
        result["json"] = str(json_path.relative_to(ROOT))
        result["svg"] = str(svg_path.relative_to(ROOT))
        result["passed"] = result["passed"] and valid
        if not valid:
            result["validation_error"] = "JSON status or SVG document did not match"
    except (OSError, ValueError, ET.ParseError) as error:
        result["passed"] = False
        result["validation_error"] = str(error)
    print(f"{'PASS' if result['passed'] else 'FAIL'} {name.upper()} JSON/SVG evidence")
    return result


def git_revision() -> str | None:
    process = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        encoding="utf-8", errors="replace", capture_output=True, check=False,
    )
    return process.stdout.strip() if process.returncode == 0 else None


def markdown_report(report: dict) -> str:
    lines = [
        "# Acceptance verification evidence",
        "",
        f"- Generated (UTC): `{report['generated_at_utc']}`",
        f"- Source revision: `{report['git_revision'] or 'unavailable'}`",
        f"- MoonBit toolchain: `{report['moon_version'] or 'unavailable'}`",
        f"- Overall: **{'PASS' if report['passed'] else 'FAIL'}**",
        "",
        "| Check | Result | Duration | Log |",
        "| --- | --- | ---: | --- |",
    ]
    for check in report["checks"]:
        lines.append(
            f"| {check['name']} | {'PASS' if check['passed'] else 'FAIL'} "
            f"| {check['duration_seconds']} s | `{Path(check['log']).name}` |"
        )
    lines.extend(
        [
            "",
            "The demo bundle contains one PASS, one travel-limit FAIL, and one "
            "INCOMPLETE JSON report and SVG. INCOMPLETE is intentionally not a pass.",
            "",
            "This report verifies repository behavior only. It does not establish "
            "event registration, organizer qualification approval, or event-chat membership.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        default="_build/acceptance",
        help="directory for logs, JSON/SVG demos, and summary (default: %(default)s)",
    )
    args = parser.parse_args()
    out = (ROOT / args.output_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)

    commands = (
        ("Resolve dependencies", ["moon", "update"], 0),
        ("Formatting", ["moon", "fmt", "--check"], 0),
        ("All-target type check", ["moon", "check", "--deny-warn", "--target", "all"], 0),
        ("All-target tests", ["moon", "test", "--deny-warn", "--target", "all"], 0),
        ("Native CLI type check", ["moon", "check", "--deny-warn", "--target", "native", "cmd/main"], 0),
        ("CLI regression corpus", [sys.executable, "scripts/check_regression_corpus.py"], 0),
        ("Reproducible README renders", [sys.executable, "scripts/generate_demo_renders.py", "--check"], 0),
    )
    checks = [
        run_command(name, command, out / f"{index:02d}-{name.lower().replace(' ', '-')}.log", expected)
        for index, (name, command, expected) in enumerate(commands, start=1)
    ]
    checks.extend(run_demo(*demo, out) for demo in DEMOS)

    version_result = subprocess.run(
        ["moon", "version", "--all"], cwd=ROOT, text=True,
        encoding="utf-8", errors="replace", capture_output=True, check=False,
    )
    report = {
        "project": "gckbbrant/gcode-preflight",
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "git_revision": git_revision(),
        "moon_version": version_result.stdout.strip() if version_result.returncode == 0 else None,
        "passed": all(check["passed"] for check in checks),
        "checks": checks,
    }
    report_path = out / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "report.md").write_text(markdown_report(report), encoding="utf-8")
    digest = hashlib.sha256(report_path.read_bytes()).hexdigest()
    try:
        display_path = out.relative_to(ROOT)
    except ValueError:
        display_path = out
    print(f"Evidence bundle: {display_path}")
    print(f"Report SHA-256: {digest}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

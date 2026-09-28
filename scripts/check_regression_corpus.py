#!/usr/bin/env python3
"""Run the checked-in G-code fixtures and compare CLI JSON/SVG to goldens."""

from __future__ import annotations

import json
import math
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "tests" / "regression"
NAMESPACE = {"svg": "http://www.w3.org/2000/svg"}


def close(actual: float, expected: float, label: str) -> None:
    if not math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-8):
        raise AssertionError(f"{label}: expected {expected}, got {actual}")


def compare_case(case: dict, output_dir: Path) -> None:
    program = (CORPUS / case["program"]).resolve()
    profile = (CORPUS / case["profile"]).resolve()
    report_path = output_dir / f"{case['id']}.json"
    svg_path = output_dir / f"{case['id']}.svg"
    command = [
        "moon",
        "run",
        "--target",
        "native",
        "cmd/main",
        "--",
        "check",
        str(program),
        "--profile",
        str(profile),
        "--json",
        str(report_path),
        "--svg",
        str(svg_path),
    ]
    process = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    expected_status = case["status"]
    expected_exit = 0 if expected_status == "Pass" else 1
    if process.returncode != expected_exit:
        raise AssertionError(
            f"{case['id']}: expected exit {expected_exit}, got "
            f"{process.returncode}\nstdout:\n{process.stdout}\n"
            f"stderr:\n{process.stderr}"
        )
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report["status"] != expected_status:
        raise AssertionError(
            f"{case['id']}: expected status {expected_status}, "
            f"got {report['status']}"
        )
    if len(report["segments"]) != case["segment_count"]:
        raise AssertionError(
            f"{case['id']}: expected {case['segment_count']} segments, "
            f"got {len(report['segments'])}"
        )
    close(report["distance_mm"], case["distance_mm"], f"{case['id']} distance")

    if "segment_kinds" in case:
        actual = [segment["kind"] for segment in report["segments"]]
        if actual != case["segment_kinds"]:
            raise AssertionError(
                f"{case['id']}: expected segment kinds "
                f"{case['segment_kinds']}, got {actual}"
            )
    if "estimated_time_model" in case:
        actual = report.get("estimated_time_model")
        expected = case["estimated_time_model"]
        if actual != expected:
            raise AssertionError(
                f"{case['id']}: expected estimated_time_model={expected}, "
                f"got {actual}"
            )
    for field, coordinate in (
        ("segment_starts_mm", "start_mm"),
        ("segment_endpoints_mm", "end_mm"),
    ):
        if field in case:
            expected_points = case[field]
            if len(expected_points) != len(report["segments"]):
                raise AssertionError(
                    f"{case['id']}: expected {len(expected_points)} {field}, "
                    f"got {len(report['segments'])} segments"
                )
            for index, (expected_point, segment) in enumerate(
                zip(expected_points, report["segments"])
            ):
                actual_point = segment[coordinate]
                for axis in ("x", "y", "z"):
                    close(
                        actual_point[axis],
                        expected_point[axis],
                        f"{case['id']} {field} {index}:{axis}",
                    )
    if "arc_sweeps_radians" in case:
        actual = [
            segment["sweep_radians"]
            for segment in report["segments"]
            if segment["kind"].endswith("Arc")
        ]
        expected = case["arc_sweeps_radians"]
        if len(actual) != len(expected):
            raise AssertionError(
                f"{case['id']}: expected {len(expected)} arc sweeps, got {len(actual)}"
            )
        for index, (observed, target) in enumerate(zip(actual, expected)):
            close(observed, target, f"{case['id']} arc sweep {index}")

    actual_diagnostics = sorted(
        (item["code"], item["line"]) for item in report["diagnostics"]
    )
    expected_diagnostics = sorted(
        (item["code"], item["line"]) for item in case["diagnostics"]
    )
    if actual_diagnostics != expected_diagnostics:
        raise AssertionError(
            f"{case['id']}: expected diagnostics {expected_diagnostics}, "
            f"got {actual_diagnostics}"
        )

    for field in ("estimate_complete", "estimated_time_seconds"):
        if field in case:
            expected = case[field]
            actual = report.get(field)
            if expected is None or isinstance(expected, bool):
                if actual != expected:
                    raise AssertionError(
                        f"{case['id']}: expected {field}={expected}, got {actual}"
                    )
            else:
                close(actual, expected, f"{case['id']} {field}")

    limits = report["travel_limits"]
    if not (
        limits["x"]["min"] < limits["x"]["max"]
        and limits["y"]["min"] < limits["y"]["max"]
    ):
        raise AssertionError(f"{case['id']}: missing valid XY travel limits")

    svg = ET.parse(svg_path).getroot()
    limit_rectangles = svg.findall("svg:rect[@class='travel-limit']", NAMESPACE)
    if len(limit_rectangles) != 1:
        raise AssertionError(
            f"{case['id']}: expected one XY travel boundary in SVG, "
            f"got {len(limit_rectangles)}"
        )
    rectangle = limit_rectangles[0]
    expected_rectangle = {
        "x": limits["x"]["min"],
        "y": -limits["y"]["max"],
        "width": limits["x"]["max"] - limits["x"]["min"],
        "height": limits["y"]["max"] - limits["y"]["min"],
    }
    for attribute, expected in expected_rectangle.items():
        close(
            float(rectangle.get(attribute, "nan")),
            expected,
            f"{case['id']} SVG travel boundary {attribute}",
        )
    travel_diagnostics = [
        item
        for item in report["diagnostics"]
        if item["code"].startswith("TRAVEL_LIMIT_")
    ]
    violation_paths = [
        path
        for path in svg.findall("svg:path", NAMESPACE)
        if "violation" in path.get("class", "").split()
    ]
    violation_points = svg.findall("svg:circle[@class='violation-point']", NAMESPACE)
    expected_point_count = sum(
        item["point_mm"] is not None for item in travel_diagnostics
    )
    if len(violation_points) != expected_point_count:
        raise AssertionError(
            f"{case['id']}: expected {expected_point_count} violation markers, "
            f"got {len(violation_points)}"
        )
    if bool(travel_diagnostics) != bool(violation_paths):
        raise AssertionError(
            f"{case['id']}: SVG violation path does not match travel diagnostics"
        )
    expected_violation_lines = sorted(
        {item["line"] for item in travel_diagnostics}
    )
    actual_violation_lines = sorted(
        int(path.get("data-line", "-1")) for path in violation_paths
    )
    if actual_violation_lines != expected_violation_lines:
        raise AssertionError(
            f"{case['id']}: expected red paths for lines "
            f"{expected_violation_lines}, got {actual_violation_lines}"
        )
    actual_svg_points = sorted(
        (float(point.get("cx", "nan")), -float(point.get("cy", "nan")))
        for point in violation_points
    )
    expected_svg_points = sorted(
        (item["point_mm"]["x"], item["point_mm"]["y"])
        for item in travel_diagnostics
        if item["point_mm"] is not None
    )
    if len(actual_svg_points) != len(expected_svg_points):
        raise AssertionError(f"{case['id']}: SVG marker count differs from report")
    for index, (actual, expected) in enumerate(
        zip(actual_svg_points, expected_svg_points)
    ):
        for axis, (observed, target) in enumerate(zip(actual, expected)):
            close(observed, target, f"{case['id']} SVG marker {index}:{axis}")

    if "violation_points_mm" in case:
        actual_points = sorted(
            (
                item["point_mm"]["x"],
                item["point_mm"]["y"],
                item["point_mm"]["z"],
            )
            for item in travel_diagnostics
        )
        expected_points = sorted(
            (item["x"], item["y"], item["z"])
            for item in case["violation_points_mm"]
        )
        if len(actual_points) != len(expected_points):
            raise AssertionError(
                f"{case['id']}: expected violation points {expected_points}, "
                f"got {actual_points}"
            )
        for index, (actual, expected) in enumerate(
            zip(actual_points, expected_points)
        ):
            for axis, (observed, target) in enumerate(zip(actual, expected)):
                close(observed, target, f"{case['id']} violation point {index}:{axis}")

    print(
        f"PASS {case['id']}: {report['status']}, "
        f"{len(report['segments'])} segments, {report['distance_mm']} mm"
    )


def main() -> int:
    cases = json.loads((CORPUS / "cases.json").read_text(encoding="utf-8"))
    output_dir = ROOT / "_build" / "regression"
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        for case in cases:
            compare_case(case, output_dir)
    except (AssertionError, OSError, json.JSONDecodeError, ET.ParseError) as error:
        print(f"Regression corpus failed: {error}", file=sys.stderr)
        return 1
    print(f"Regression corpus passed: {len(cases)} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

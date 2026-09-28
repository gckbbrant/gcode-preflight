#!/usr/bin/env python3
"""Verify the architecture deck is a one-slide, editable PowerPoint diagram."""

from __future__ import annotations

import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PPTX = ROOT / "docs/architecture/cnc-gcode-preflight-architecture.pptx"
SVG = ROOT / "docs/images/architecture.svg"
P_NS = "http://schemas.openxmlformats.org/presentationml/2006/main"
A_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
NS = {"p": P_NS, "a": A_NS}
EXPECTED_SIZE = ("15240000", "8572500")
REQUIRED_LABELS = (
    "CNC G-code 预检器架构",
    "analyze(program, profile)",
    "词法解析",
    "模态状态",
    "几何与行程",
    "周期估算",
    "AnalysisReport",
    "CLI 摘要",
    "JSON 报告",
    "SVG 刀路图",
    "PASS",
    "FAIL",
    "INCOMPLETE",
)


def check() -> list[str]:
    errors: list[str] = []
    if not SVG.is_file():
        errors.append(f"Missing vector source: {SVG.relative_to(ROOT)}")
    else:
        try:
            svg_root = ET.parse(SVG).getroot()
            svg_text = "".join(svg_root.itertext())
            if svg_root.tag != "{http://www.w3.org/2000/svg}svg":
                errors.append("Architecture vector source is not an SVG document")
            if "CNC G-code 预检器架构" not in svg_text:
                errors.append("Architecture SVG is missing the project title")
        except (OSError, ET.ParseError) as error:
            errors.append(f"Could not inspect architecture SVG: {error}")

    if not PPTX.is_file():
        errors.append(f"Missing deck: {PPTX.relative_to(ROOT)}")
        return errors

    try:
        with zipfile.ZipFile(PPTX) as archive:
            bad_member = archive.testzip()
            if bad_member:
                errors.append(f"Corrupt PPTX member: {bad_member}")
            presentation = ET.fromstring(archive.read("ppt/presentation.xml"))
            slide_paths = sorted(
                name for name in archive.namelist()
                if name.startswith("ppt/slides/slide") and name.endswith(".xml")
                and "/_rels/" not in name
            )
            slide_size = presentation.find("p:sldSz", NS)
            if slide_size is None or (slide_size.get("cx"), slide_size.get("cy")) != EXPECTED_SIZE:
                errors.append("Slide size must be 16:9 (15240000 x 8572500 EMU)")
            if len(slide_paths) != 1:
                errors.append(f"Expected 1 slide XML, found {len(slide_paths)}")
            if len(slide_paths) == 1:
                slide = ET.fromstring(archive.read(slide_paths[0]))
                native_shapes = slide.findall(".//p:sp", NS)
                pictures = slide.findall(".//p:pic", NS)
                images = slide.findall(".//a:blip", NS)
                text = "".join(node.text or "" for node in slide.findall(".//a:t", NS))
                if len(native_shapes) < 60:
                    errors.append(f"Expected at least 60 native shapes, found {len(native_shapes)}")
                if pictures or images:
                    errors.append(
                        f"Expected editable vector shapes and text, found {len(pictures)} picture shapes and {len(images)} embedded images"
                    )
                for label in REQUIRED_LABELS:
                    if label not in text:
                        errors.append(f"Missing required diagram label: {label}")
    except (OSError, zipfile.BadZipFile, KeyError, ET.ParseError) as error:
        errors.append(f"Could not inspect PPTX package: {error}")

    return errors


def main() -> int:
    errors = check()
    if errors:
        for error in errors:
            print(f"FAIL {error}")
        return 1
    print("PASS architecture PPTX: 1 slide, 16:9, native editable shapes, expected labels")
    return 0


if __name__ == "__main__":
    sys.exit(main())

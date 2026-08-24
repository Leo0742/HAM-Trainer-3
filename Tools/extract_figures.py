#!/usr/bin/env python3
"""Extract the four neutral, answer-free source figures required by category 3."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_DPI = 160
OUTPUT_DPI = 220

# Coordinates were independently inspected against the preserved 2015 PDF.
# Values are page, x, y, width, height at BASE_DPI.
ASSETS = {
    "cept-visit-prefixes.png": {
        "page": 124, "crop": (135, 315, 1055, 735),
        "questions": [22, 23], "purpose": "Рисунок 1: префиксы ON (Бельгия) и OE (Австрия)",
    },
    "harec-national-licenses.png": {
        "page": 127, "crop": (135, 780, 1055, 680),
        "questions": [32], "purpose": "Рисунок 2: бельгийская лицензия класса A для HAREC",
    },
    "fm-transmitter.png": {
        "page": 162, "crop": (145, 275, 340, 190),
        "questions": [173, 174, 175, 176], "purpose": "Общая нейтральная схема FM-передатчика 1 -> 2 -> 4",
    },
    "superhet-receiver.png": {
        "page": 163, "crop": (140, 580, 345, 165),
        "questions": [177, 178, 179, 180], "purpose": "Общая нейтральная схема супергетеродинного приёмника",
    },
}


def scaled(value: int) -> int:
    return round(value * OUTPUT_DPI / BASE_DPI)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, default=ROOT / "ExamSources" / "Справочник_КЭ.pdf")
    parser.add_argument("--output", type=Path, default=ROOT / "Content" / "diagrams" / "questions")
    args = parser.parse_args()
    if not args.reference.is_file():
        raise SystemExit(f"Reference PDF not found: {args.reference}")
    if shutil.which("pdftoppm") is None:
        raise SystemExit("pdftoppm is required")

    args.output.mkdir(parents=True, exist_ok=True)
    question_entries = []
    for filename, spec in ASSETS.items():
        x, y, width, height = map(scaled, spec["crop"])
        target = args.output / filename
        subprocess.run([
            "pdftoppm", "-f", str(spec["page"]), "-l", str(spec["page"]),
            "-r", str(OUTPUT_DPI), "-png", "-singlefile",
            "-x", str(x), "-y", str(y), "-W", str(width), "-H", str(height),
            str(args.reference), str(target.with_suffix("")),
        ], check=True)
        if target.stat().st_size == 0:
            raise SystemExit(f"empty extracted asset: {target}")
        for number in spec["questions"]:
            question_entries.append({
                "examNumber": number,
                "sourceDocument": "Справочник_КЭ.pdf",
                "sourcePDFPage": spec["page"],
                "asset": f"diagrams/questions/{filename}",
                "purpose": spec["purpose"],
                "visuallyInspected": True,
            })

    manifest = {
        "schemaVersion": 1,
        "renderDPI": OUTPUT_DPI,
        "answerKeyExcluded": True,
        "questions": sorted(question_entries, key=lambda item: item["examNumber"]),
    }
    (args.output / "figure-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Extracted {len(ASSETS)} shared assets for {len(question_entries)} questions")


if __name__ == "__main__":
    main()

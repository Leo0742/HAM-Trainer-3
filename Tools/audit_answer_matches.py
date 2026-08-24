#!/usr/bin/env python3
"""Verify every guide answer against an official option and write permanent reports."""

from __future__ import annotations

import difflib
import json
import re
from pathlib import Path

from category_profile import EXPECTED_NUMBERS

ROOT = Path(__file__).resolve().parents[1]


def normalized(value: str) -> str:
    value = value.lower().replace("ё", "е")
    value = value.replace("≤", "<=").replace("≥", ">=")
    return re.sub(r"[^a-zа-я0-9<>=]+", "", value)


def main() -> None:
    questions = [
        question
        for question in json.loads((ROOT / "ContentRaw" / "questions-imported.json").read_text(encoding="utf-8"))
        if question["examNumber"] in EXPECTED_NUMBERS
    ]
    overrides = json.loads((ROOT / "ContentOverrides" / "question-overrides.json").read_text(encoding="utf-8")).get("questions", {})
    rows = []
    unresolved = []
    for question in questions:
        number = question["examNumber"]
        guide = question["officialCorrectAnswerText"]
        target = normalized(guide)
        options = question["options"]
        exact = [index for index, option in enumerate(options) if normalized(option["text"]) == target]
        override = overrides.get(str(number), {})
        if "correctOptionIndex" in override:
            index = int(override["correctOptionIndex"])
            method = "manual"
            confidence = 1.0
            note = override.get("answerMatchNote", "Explicit source-checked override.")
        elif exact:
            index = exact[0]
            method = "exact"
            confidence = 1.0
            note = "Normalized guide answer exactly matches the official option."
        else:
            scores = [difflib.SequenceMatcher(None, target, normalized(option["text"])).ratio() for option in options]
            index = max(range(len(scores)), key=scores.__getitem__)
            method = "fuzzy"
            confidence = scores[index]
            note = "UNRESOLVED: fuzzy match has no explicit source-checked override."
            unresolved.append(number)

        matched = options[index]
        production_id = override.get("correctOptionId", question["correctOptionId"])
        production = next(option for option in options if option["id"] == production_id)
        source = override.get("sourceReference", question["sourceReference"])
        row = {
            "questionNumber": number,
            "guideAnswer": guide,
            "matchedOfficialOption": matched["text"],
            "matchedOptionIndex": index,
            "productionCorrectOptionId": production["id"],
            "confidence": round(confidence, 6),
            "method": method,
            "note": note,
            "guidePage": source["explanationPage"],
            "officialBankPage": source["page"],
        }
        if production["id"] != matched["id"]:
            unresolved.append(number)
            row["note"] = "UNRESOLVED: production correctOptionId differs from the verified match."
        rows.append(row)

    report = {
        "generatedOn": "reproducible",
        "total": len(rows),
        "exact": sum(row["method"] == "exact" for row in rows),
        "manual": sum(row["method"] == "manual" for row in rows),
        "fuzzy": sum(row["method"] == "fuzzy" for row in rows),
        "unresolved": sorted(set(unresolved)),
        "matches": rows,
    }
    docs = ROOT / "docs"
    docs.mkdir(exist_ok=True)
    (docs / "answer-match-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    manual_lines = "\n".join(
        f"- № {row['questionNumber']}: option {row['matchedOptionIndex'] + 1}; {row['note']}"
        for row in rows if row["method"] == "manual"
    ) or "- None."
    markdown = f"""# Answer-match audit

Generated: {report['generatedOn']}

- Questions: **{report['total']}**
- Exact normalized matches: **{report['exact']}**
- Explicit manual matches: **{report['manual']}**
- Unverified fuzzy matches: **{report['fuzzy']}**
- Unresolved production mappings: **{len(report['unresolved'])}**

Every non-exact match must be represented by an explicit `correctOptionIndex` override. The complete per-question evidence, including both source page numbers, is in [`answer-match-audit.json`](answer-match-audit.json).

## Manual source checks

{manual_lines}
"""
    (docs / "answer-match-audit.md").write_text(markdown, encoding="utf-8")
    if unresolved:
        raise SystemExit(f"Unresolved answer matches: {sorted(set(unresolved))}")
    print(f"Answer matches OK: {len(rows)} total; {report['exact']} exact; {report['manual']} manual; 0 fuzzy")


if __name__ == "__main__":
    main()

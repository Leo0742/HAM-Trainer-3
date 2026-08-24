#!/usr/bin/env python3
"""Write reproducible authored-content, source, glossary, and asset audits."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

from category_profile import BANK_COUNT

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Content"
DOCS = ROOT / "docs"
AUTHORED_PATH = ROOT / "ContentAuthored" / "third-category-218-explanations.json"
AUTHORED_SHA256 = "c438938b5733be90b80eb87b2ec782c952bbff47378b54de9fc23647199044a1"
GLOSSARY_AUTHORED_PATH = ROOT / "ContentAuthored" / "built-in-glossary-176.json"
GLOSSARY_AUTHORED_SHA256 = "2d3902bb049064066bc71766405237ab7ab39cc7b2b123de249700a1230bc1d3"
EXPECTED_SOURCE_HASHES = {
    "Справочник_КЭ.pdf": "8108c82eb316069167a7ae3e525a9991637e2f547f12fbbde637e684dbad55d7",
    "radiolyubitel_2_category_guide_2026.pdf": "163c01bded0c4b5cee92892948f15eab32b226f6f0bd0edc70f0beecd6317749",
}
DIRECT_FIELDS = ("explanationShort", "explanationBeginner", "explanationReasoning", "memoryHint")


def normalized(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower().replace("ё", "е"))


def main() -> None:
    subprocess.run(["python3", str(ROOT / "Tools/validate_content.py")], check=True)
    subprocess.run(["python3", str(ROOT / "Tools/audit_answer_matches.py")], check=True)

    questions = json.loads((CONTENT / "questions.json").read_text(encoding="utf-8"))
    raw = json.loads((ROOT / "ContentRaw/questions-imported.json").read_text(encoding="utf-8"))
    glossary = json.loads((CONTENT / "glossary.json").read_text(encoding="utf-8"))
    answer_audit = json.loads((DOCS / "answer-match-audit.json").read_text(encoding="utf-8"))
    authored_bytes = AUTHORED_PATH.read_bytes()
    authored_digest = hashlib.sha256(authored_bytes).hexdigest()
    authored = json.loads(authored_bytes)["questions"]
    glossary_authored_bytes = GLOSSARY_AUTHORED_PATH.read_bytes()
    glossary_authored_digest = hashlib.sha256(glossary_authored_bytes).hexdigest()
    glossary_authored = json.loads(glossary_authored_bytes)["entries"]
    by_number = {q["examNumber"]: q for q in questions}
    raw_by_number = {q["examNumber"]: q for q in raw}
    overrides = json.loads((ROOT / "ContentOverrides/question-overrides.json").read_text(encoding="utf-8")).get("questions", {})

    def source_checked_options(number: int) -> list[dict]:
        option_text = overrides.get(str(number), {}).get("optionTextById", {})
        return [
            {**option, "text": option_text.get(option["id"], option["text"])}
            for option in raw_by_number[number]["options"]
        ]

    unchanged_stems = sum(by_number[n]["stem"] == raw_by_number[n]["stem"] for n in by_number)
    unchanged_options = sum(by_number[n]["options"] == source_checked_options(n) for n in by_number)
    resolved_correct_ids = sum(any(o["id"] == q["correctOptionId"] for o in q["options"]) for q in questions)
    authored_exact = sum(
        all(q[field] == authored[str(q["examNumber"])][field] for field in DIRECT_FIELDS)
        for q in questions
    )
    fallback = sorted(q["examNumber"] for q in questions if not all(
        q[field] == authored[str(q["examNumber"])][field] for field in DIRECT_FIELDS
    ))
    unresolved_wrong = sorted(q["examNumber"] for q in questions if
        set(q["wrongOptionExplanations"]) != {o["id"] for o in q["options"] if o["id"] != q["correctOptionId"]}
        or len(q["wrongOptionExplanations"]) != 3
    )

    term_ids = {entry["id"] for entry in glossary}
    unresolved_glossary = sorted(set(term for q in questions for term in q.get("glossaryTerms", [])) - term_ids)
    identical_from_zero = sorted(
        entry["id"] for entry in glossary
        if normalized(entry["shortDefinition"]) == normalized(entry["fromZero"])
    )
    glossary_authored_by_term = {entry["term"]: entry for entry in glossary_authored}
    glossary_exact = sum(
        entry["term"] in glossary_authored_by_term and all(
            entry[field] == glossary_authored_by_term[entry["term"]][field]
            for field in ("shortDefinition", "fromZero", "radioExample")
        )
        for entry in glossary
    )
    original_assets = sorted({q["figureAsset"] for q in questions if q.get("figureAsset")})
    teaching_assets = sorted({
        *[entry["diagramAsset"] for entry in glossary if entry.get("diagramAsset")],
        *[q["teachingDiagramAsset"] for q in questions if q.get("teachingDiagramAsset")],
    })
    missing_assets = sorted(asset for asset in original_assets + teaching_assets if not (CONTENT / asset).is_file())
    unresolved_requested_exam_figures = sorted(q["examNumber"] for q in questions if q.get("useExamFigure") and not q.get("figureAsset"))

    source_files = []
    for name, expected_digest in EXPECTED_SOURCE_HASHES.items():
        path = ROOT / "ExamSources" / name
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        source_files.append({
            "file": name, "bytes": path.stat().st_size, "sha256": digest,
            "unchanged": digest == expected_digest,
        })

    legacy_sources = [
        str(path.relative_to(ROOT)) for path in [
            ROOT / "Tools/curate_content.py",
            *sorted((ROOT / "ContentOverrides").glob("questions-*.json")),
        ] if path.exists()
    ]
    report = {
        "generatedOn": "reproducible",
        "authoredSource": {
            "file": str(AUTHORED_PATH.relative_to(ROOT)),
            "sha256": authored_digest,
            "checksumMatches": authored_digest == AUTHORED_SHA256,
            "totalQuestions": len(questions),
            "authoredEducationalRecords": authored_exact,
            "fallbackGeneratedEducationalRecords": len(fallback),
            "fallbackQuestionIds": fallback,
            "unresolvedWrongOptionMappings": unresolved_wrong,
            "unresolvedGlossaryMappings": unresolved_glossary,
            "legacyProductionExplanationSources": legacy_sources,
            "manualSourceResolutions": {
                "cleanTextToStableOptionId": [23, 32],
                "suppliedWrongMapRepairUsingExactAuthoredShortText": [],
                "officialBankExtractionOrAnswerFix": [119, 191, 201],
            },
            "method": "Authored means an exact record in the immutable checksum-verified ContentAuthored JSON. No generated fallback is counted or permitted.",
        },
        "structural": {
            "uniqueExamNumbers": len(by_number),
            "resolvedCorrectOptionIds": resolved_correct_ids,
            "unchangedOfficialStems": unchanged_stems,
            "unchangedOfficialOptionSets": unchanged_options,
        },
        "answerMatching": {
            "exact": answer_audit["exact"], "manual": answer_audit["manual"],
            "unresolvedFuzzy": answer_audit["fuzzy"], "unresolved": answer_audit["unresolved"],
        },
        "glossary": {
            "entries": len(glossary),
            "authoredSource": str(GLOSSARY_AUTHORED_PATH.relative_to(ROOT)),
            "authoredSha256": glossary_authored_digest,
            "checksumMatches": glossary_authored_digest == GLOSSARY_AUTHORED_SHA256,
            "authoredEducationalRecords": glossary_exact,
            "identicalNormalizedShortAndFromZero": identical_from_zero,
        },
        "assets": {
            "examFigures": len(original_assets), "teachingDiagrams": len(teaching_assets),
            "missingAssets": missing_assets,
            "unresolvedRequestedExamFigures": unresolved_requested_exam_figures,
        },
        "sourceFiles": source_files,
    }

    failures = []
    if len(questions) != len(authored) or authored_exact != BANK_COUNT or fallback: failures.append("authored coverage")
    if authored_digest != AUTHORED_SHA256: failures.append("authored checksum")
    if glossary_authored_digest != GLOSSARY_AUTHORED_SHA256: failures.append("authored glossary checksum")
    if unresolved_wrong or unresolved_glossary: failures.append("content mappings")
    if legacy_sources: failures.append("legacy generated explanation source")
    if unchanged_stems != BANK_COUNT or unchanged_options != BANK_COUNT: failures.append("official wording/options")
    if resolved_correct_ids != BANK_COUNT: failures.append("correct option IDs")
    if answer_audit["fuzzy"] or answer_audit["unresolved"]: failures.append("answer matching")
    if glossary_exact != len(glossary): failures.append("authored glossary coverage")
    if missing_assets or unresolved_requested_exam_figures: failures.append("assets")
    if not all(item["unchanged"] for item in source_files): failures.append("source PDF hash")
    report["failures"] = failures

    DOCS.mkdir(exist_ok=True)
    (DOCS / "content-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    source_lines = "\n".join(f"- `{item['file']}` — SHA-256 `{item['sha256']}`" for item in source_files)
    markdown = f"""# Content audit

Generated: reproducible

## Authored educational source

- Total questions: **{len(questions)}**.
- Authored educational records: **{authored_exact}**.
- Fallback-generated educational records: **{len(fallback)}**.
- Unresolved wrong-option mappings: **{len(unresolved_wrong)}**.
- Unresolved glossary mappings: **{len(unresolved_glossary)}**.
- Source: `{AUTHORED_PATH.relative_to(ROOT)}`; SHA-256 `{authored_digest}`.

“Authored” means an exact record in the immutable checksum-verified source file. The audit does not assign an automated educational-quality score.

## Structural, answer, glossary, and assets

- Official stems unchanged / option sets equal to the raw source plus documented source-cleanup overrides: **{unchanged_stems}/{BANK_COUNT}** / **{unchanged_options}/{BANK_COUNT}**.
- Resolved correct option IDs: **{resolved_correct_ids}/{BANK_COUNT}**.
- Answer matches exact / manual / fuzzy: **{answer_audit['exact']} / {answer_audit['manual']} / {answer_audit['fuzzy']}**.
- Built-in glossary entries: **{len(glossary)}**; exact authored educational records: **{glossary_exact}**; normalized `fromZero == shortDefinition`: **{len(identical_from_zero)}**.
- Glossary source: `{GLOSSARY_AUTHORED_PATH.relative_to(ROOT)}`; SHA-256 `{glossary_authored_digest}`.
- Exam figures / teaching diagrams: **{len(original_assets)} / {len(teaching_assets)}**; missing assets: **{len(missing_assets)}**.

## Preserved source files

{source_lines}

Machine-readable details: [`content-audit.json`](content-audit.json) and [`answer-match-audit.json`](answer-match-audit.json).
"""
    (DOCS / "content-audit.md").write_text(markdown, encoding="utf-8")
    if failures:
        raise SystemExit(f"Content audit failures: {failures}")
    print(
        f"Content audit OK: {BANK_COUNT} total; {BANK_COUNT} authored; 0 fallback; "
        "0 wrong-option mappings; 0 glossary mappings"
    )


if __name__ == "__main__":
    main()

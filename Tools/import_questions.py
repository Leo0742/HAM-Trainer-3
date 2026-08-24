#!/usr/bin/env python3
"""Extract the normalized HAM Trainer source bank from the supplied PDFs.

The importer writes ContentRaw only, then invokes build_content.py. Keeping raw
extraction separate from the teaching layer means a later PDF import cannot
erase curated explanations or overrides.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

SECOND_CATEGORY = set(range(1, 39)) | set(range(47, 99)) | set(range(100, 375)) | set(range(387, 427))


def compact(value: str) -> str:
    value = value.replace("\u00ad", "").replace("\f", "\n")
    value = re.sub(r"-\s*\n\s*(?=[а-яё])", "", value, flags=re.I)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def normalized(value: str) -> str:
    value = compact(value).lower().replace("ё", "е")
    value = value.replace("–", "-").replace("—", "-").replace("…", "...")
    value = value.replace("≤", "<=").replace("≥", ">=")
    return re.sub(r"[^a-zа-я0-9<>=]+", "", value)


@dataclass
class GuideEntry:
    number: int
    stem: str
    answer: str
    explanation: str
    question_type: str
    topic: str
    page: int


@dataclass
class ReferenceEntry:
    number: int
    stem: str
    options: list[str]
    page: int


def run_text_extract(pdf: Path, output: Path) -> str:
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["pdftotext", "-layout", str(pdf), str(output)], check=True)
    return output.read_text(encoding="utf-8")


def parse_guide(raw: str) -> dict[int, GuideEntry]:
    starts = list(re.finditer(r"(?m)^№\s*(\d+)\.\s*", raw))
    result: dict[int, GuideEntry] = {}
    for index, match in enumerate(starts):
        number = int(match.group(1))
        if number not in SECOND_CATEGORY:
            continue
        block_end = starts[index + 1].start() if index + 1 < len(starts) else len(raw)
        block = raw[match.end():block_end]
        answer_marker = re.search(r"\n\s*Правильный ответ:\s*", block)
        explanation_marker = re.search(r"\n\s*Пояснение\.\s*", block)
        metadata_marker = re.search(r"\n\s*Тип:\s*(.*?)\.\s*Тема:\s*(.*?)\.\s*(?:\n|$)", block)
        if not (answer_marker and explanation_marker and metadata_marker):
            raise ValueError(f"Guide entry {number} has an unexpected structure")
        stem = compact(block[:answer_marker.start()])
        answer = compact(block[answer_marker.end():explanation_marker.start()])
        explanation = compact(block[explanation_marker.end():metadata_marker.start()])
        result[number] = GuideEntry(
            number=number,
            stem=stem,
            answer=answer,
            explanation=explanation,
            question_type=compact(metadata_marker.group(1)),
            topic=compact(metadata_marker.group(2)),
            page=raw[:match.start()].count("\f") + 1,
        )
    if set(result) != SECOND_CATEGORY:
        missing = sorted(SECOND_CATEGORY - set(result))
        extra = sorted(set(result) - SECOND_CATEGORY)
        raise ValueError(f"Guide selection mismatch; missing={missing}, extra={extra}")
    return result


def strip_reference_noise(value: str) -> str:
    value = re.sub(r"(?m)^\s*\d{1,3}\s*\n\f", "\n", value)
    value = re.sub(r"\n\s*\d{1,3}\s*$", "", value)
    value = value.replace("\f", "\n")
    return compact(value)


def parse_reference(raw: str) -> dict[int, ReferenceEntry]:
    # A few compact rows place two answer labels on one line (for example
    # "a) 28 MHz.   c) 42 MHz."). Turn only labels preceded by wide spacing
    # into regular line-oriented options.
    raw = re.sub(r"(?m)[ \t]{2,}([a-d]\))\s*", r"\n\1 ", raw)
    starts = list(re.finditer(r"(?m)^\f?Вопрос №\s*(\d+)(?:\s*\([^\n]*\))?\s*[;*]?\s*$", raw))
    result: dict[int, ReferenceEntry] = {}
    for index, match in enumerate(starts):
        number = int(match.group(1))
        block_end = starts[index + 1].start() if index + 1 < len(starts) else len(raw)
        block = raw[match.end():block_end]
        if number == 426 and "\nПримечания:" in block:
            block = block.split("\nПримечания:", 1)[0]
        option_matches = list(re.finditer(r"(?m)^\s*([a-d])\)\s*", block))
        if not option_matches:
            continue
        stem = strip_reference_noise(block[:option_matches[0].start()])
        options: list[str] = []
        for option_index, option_match in enumerate(option_matches):
            end = option_matches[option_index + 1].start() if option_index + 1 < len(option_matches) else len(block)
            options.append(strip_reference_noise(block[option_match.end():end]))
        if number == 33 and len(options) == 3 and "dc Заочно" in options[1]:
            headquarters, online = options[1].split("dc Заочно", 1)
            # Preserve the existing stable option IDs while restoring the four
            # source choices that PDF extraction had glued together.
            options = [options[0], headquarters.strip(), options[2], f"Заочно{online}".strip()]
        result[number] = ReferenceEntry(
            number=number,
            stem=stem,
            options=options,
            page=raw[:match.start()].count("\f") + 1,
        )
    missing = sorted(SECOND_CATEGORY - set(result))
    if missing:
        raise ValueError(f"Reference PDF is missing parsed questions: {missing}")
    return result


def best_option(answer: str, options: list[str]) -> tuple[int, float]:
    target = normalized(answer)
    scores = []
    for option in options:
        candidate = normalized(option)
        if target == candidate:
            score = 1.0
        elif target in candidate or candidate in target:
            score = min(len(target), len(candidate)) / max(len(target), len(candidate))
        else:
            score = difflib.SequenceMatcher(None, target, candidate).ratio()
        scores.append(score)
    winner = max(range(len(scores)), key=scores.__getitem__)
    return winner, scores[winner]


def load_overrides(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload.get("questions", {})


def glossary_terms(text: str, glossary: list[dict]) -> list[str]:
    haystack = text.lower().replace("ё", "е")
    found = []
    for term in glossary:
        aliases = [term["term"], *term.get("aliases", [])]
        if any(alias.lower().replace("ё", "е") in haystack for alias in aliases):
            found.append(term["id"])
    return found[:8]


def build_questions(guide: dict[int, GuideEntry], reference: dict[int, ReferenceEntry], glossary: list[dict], overrides: dict[str, dict]) -> tuple[list[dict], list[dict]]:
    questions = []
    report = []
    for number in sorted(SECOND_CATEGORY):
        g = guide[number]
        r = reference[number]
        match_index, confidence = best_option(g.answer, r.options)
        override = overrides.get(str(number), {})
        method = "exact" if confidence == 1.0 else "fuzzy"
        if "correctOptionIndex" in override:
            match_index = int(override["correctOptionIndex"])
            confidence = 1.0
            method = "manual"
        qid = f"q-{number:03d}"
        options = [{"id": f"{qid}-option-{i + 1}", "text": text} for i, text in enumerate(r.options)]
        is_figure = "рисунк" in g.question_type.lower()
        figure = f"diagrams/reference-page-{r.page}.png" if is_figure else None
        short = g.explanation
        beginner = (
            f"Правильный ответ: {g.answer}\n\n{g.explanation}\n\n"
            "Если слова в формулировке незнакомы, откройте выделенные термины: карточка даст простое определение и пример из радиостанции."
        )
        reasoning = f"Сначала определите, что именно проверяет вопрос. Затем сопоставьте это с правилом: {g.explanation}"
        wrong = {
            option["id"]: (
                f"Вариант «{option['text']}» не соответствует правилу из экзаменационного банка. "
                f"Ориентир для проверки: {g.explanation}"
            )
            for i, option in enumerate(options) if i != match_index
        }
        question = {
            "id": qid,
            "examNumber": number,
            "stem": r.stem or g.stem,
            "options": options,
            "correctOptionId": options[match_index]["id"],
            "officialCorrectAnswerText": g.answer,
            "topic": g.topic,
            "subtopic": override.get("subtopic", g.topic),
            "type": g.question_type,
            "explanationShort": short,
            "explanationBeginner": beginner,
            "explanationReasoning": reasoning,
            "wrongOptionExplanations": wrong,
            "memoryHint": override.get("memoryHint", f"Запомните смысл: {g.answer}"),
            "glossaryTerms": glossary_terms(f"{r.stem} {g.explanation}", glossary),
            "figureAsset": figure,
            "sourceReference": {
                "document": "Справочник_КЭ.pdf",
                "page": r.page,
                "sourceQuestionNumber": number,
                "explanationDocument": "radiolyubitel_2_category_guide_2026.pdf",
                "explanationPage": g.page,
            },
            "legalHistoricalNote": override.get("legalHistoricalNote"),
        }
        question.update({k: v for k, v in override.items() if k not in {"correctOptionIndex", "answerMatchNote"}})
        questions.append(question)
        report.append({"number": number, "confidence": round(confidence, 6), "method": method, "answer": g.answer, "matched": r.options[match_index]})
    return questions, report


def extract_figures(reference_pdf: Path, questions: list[dict], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    pages = sorted({q["sourceReference"]["page"] for q in questions if q.get("figureAsset")})
    for page in pages:
        target = output_dir / f"reference-page-{page}.png"
        if target.exists():
            continue
        subprocess.run([
            "pdftoppm", "-f", str(page), "-l", str(page), "-r", "130", "-png", "-singlefile",
            str(reference_pdf), str(target.with_suffix("")),
        ], check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--guide", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    project = args.project.resolve()
    cache = project / ".build" / "content-import"
    guide_raw = run_text_extract(args.guide, cache / "guide.txt")
    reference_raw = run_text_extract(args.reference, cache / "reference.txt")
    glossary = json.loads((project / "Content" / "glossary.json").read_text(encoding="utf-8"))
    overrides = load_overrides(project / "ContentOverrides" / "question-overrides.json")
    questions, report = build_questions(parse_guide(guide_raw), parse_reference(reference_raw), glossary, overrides)
    raw_dir = project / "ContentRaw"
    raw_dir.mkdir(exist_ok=True)
    output = raw_dir / "questions-imported.json"
    output.write_text(json.dumps(questions, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    topics = [{"id": f"topic-{index + 1:02d}", "title": title, "questionCount": sum(q["topic"] == title for q in questions)} for index, title in enumerate(sorted({q["topic"] for q in questions}))]
    (raw_dir / "topics-imported.json").write_text(json.dumps(topics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    source_map = {q["id"]: q["sourceReference"] for q in questions}
    (raw_dir / "source-map-imported.json").write_text(json.dumps(source_map, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (cache / "match-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    fuzzy = [entry for entry in report if entry["method"] == "fuzzy"]
    if fuzzy:
        raise ValueError(f"{len(fuzzy)} fuzzy answer matches require explicit overrides; see {cache / 'match-report.json'}")
    subprocess.run([sys.executable, str(project / "Tools" / "audit_answer_matches.py")], check=True)
    subprocess.run([
        sys.executable, str(project / "Tools" / "extract_figures.py"),
        "--reference", str(args.reference),
    ], check=True)
    subprocess.run([sys.executable, str(project / "Tools" / "build_content.py")], check=True)
    print(f"Imported and enriched {len(questions)} questions; {sum(q['figureAsset'] is not None for q in questions)} use figures")


if __name__ == "__main__":
    main()

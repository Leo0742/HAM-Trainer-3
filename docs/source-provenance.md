# Source provenance

## Preserved documents

- `Справочник_КЭ.pdf` — 233 pages, 2015 local edition by А. Н. Заморока; stems, four options, numbering, and figures; SHA-256 `8108c82eb316069167a7ae3e525a9991637e2f547f12fbbde637e684dbad55d7`.
- `radiolyubitel_2_category_guide_2026.pdf` — 104 pages, dated 1 August 2026; topic labels, correct-answer text, and explanations used for the selected questions; SHA-256 `163c01bded0c4b5cee92892948f15eab32b226f6f0bd0edc70f0beecd6317749`.

The guide is a larger second-category collection. HAM Trainer 3 does not adopt its category definition: `CategoryProfile` selects only the exact 218 numbers requested for category 3.

The SwiftUI architecture was copied read-only from `Leo0742/HAM-Trainer` at verified `main` commit `697cb9dca1ab1f0b832ef97d58810acdda7e1ebd`. That repository was not modified; this implementation and its history live only in `Leo0742/HAM-Trainer-3`.

## Source priority

1. The handbook supplies exact question wording, four options, numbering, and figures.
2. The guide supplies topic, answer text, and its authored explanatory basis.
3. `third-category-218-explanations.json` supplies the immutable educational layer for only the selected bank.
4. `question-overrides.json` applies explicit source-checked resolutions last.

Question 201 retains the documented guide/source wording difference. Questions 23 and 32 have only OCR spillover removed from their fourth option; the printed table remains a separate figure and the intended option text is recorded in the override.

## Reproducible pipeline

`ContentRaw/` preserves normalized extraction. `build_content.py` verifies authored hashes, filters the exact number set, resolves stable option/glossary IDs, maps four shared figures to 11 questions, and emits `Content/`. `source-map.json` links every card to both documents and page numbers.

`extract_figures.py` uses fixed page/crop specifications and writes `figure-manifest.json`. The crops exclude printed red answer keys. `audit_answer_matches.py` records 215 exact and 3 explicit manual answer matches; `audit_content.py` requires zero fallback and verifies both PDF hashes.

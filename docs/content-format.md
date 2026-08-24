# Content format

`Content/questions.json` is an array of 218 immutable `Question` objects. Each record has a stable ID, official exam number and stem, four stable-ID options, `correctOptionId`, official answer text, topic metadata, authored explanation layers, three wrong-option explanations, glossary IDs, optional figure/teaching assets, and a two-document `sourceReference`.

Mutable attempts, notes, bookmarks, review state, concept state, and personal glossary entries are intentionally absent; they live only in the HAM Trainer 3 progress store.

## Layers

- `ContentRaw/questions-imported.json`: normalized extraction retained for audit.
- `ContentAuthored/third-category-218-explanations.json`: checksum-verified educational source for the exact category-3 set.
- `ContentOverrides/question-overrides.json`: explicit source-checked extraction/answer resolutions only.
- `Content/questions.json`, `glossary.json`, `topics.json`, `source-map.json`: reproducible runtime outputs.

The builder never edits the authored source and never generates fallback explanations. It resolves clean wrong-option text to stable IDs, applies two documented OCR cleanup overrides, and filters the immutable 176-term authored glossary to the 127 IDs actually referenced by this bank. Generated runtime files should not be edited directly.

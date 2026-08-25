# HAM Trainer 3 — authored content

Production content is assembled from two checksum-verified authored sources:

- `third-category-218-explanations.json` — exactly 218 question records, SHA-256 `13c2f3c8d84c43078362399a23a25e5b802bbf4c5ea20778f3ff1373f736f489`;
- `built-in-glossary-176.json` — the immutable glossary superset, SHA-256 `2d3902bb049064066bc71766405237ab7ab39cc7b2b123de249700a1230bc1d3`.

The question file covers only `1–34`, `47–98`, `100–135`, `150–226`, `387–391`, and `409–422`. Each record contains concise, beginner, reasoning, three wrong-option explanations, memory hint, glossary labels, and optional figure/teaching-diagram metadata.

These files are educational source data. Build and CI validate and merge them but must not paraphrase, regenerate, or overwrite them. Official stems, options, correct option IDs, and figures come from the preserved exam sources. Clean authored option labels are bound to stable option IDs; displayed letters are never used because options can be shuffled.

The runtime glossary is filtered to the 127 entries referenced by this bank. The full 176-entry source remains immutable so its hash and provenance stay reproducible.

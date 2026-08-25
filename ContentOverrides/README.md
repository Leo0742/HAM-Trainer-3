# Source-guide overrides

`question-overrides.json` is consumed by `Tools/import_questions.py` while it parses the preserved larger source guide, before `CategoryProfile` filters the production bank to 218 questions.

Overrides 36, 233, and 359 are outside the HAM Trainer 3 runtime set, but they are intentionally retained: each resolves an otherwise non-exact answer match in that larger reproducible import. Removing them would make a full source import fail before the category-3 subset is built.

Runtime-relevant overrides remain limited to documented OCR cleanup or source-checked answer resolutions.

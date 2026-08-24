# Testing and verification

`Tools/run_tests.sh` compiles production models, persistence, and scheduler code into a native runner with no external test dependency.

The 54 checks cover:

- exact 5/10/20/40/80 distances, failures, reveal, lapse, restart persistence, eligibility, reinsertion gap, and appearance cap;
- safe Back/Forward history and dynamic Smart Study refresh;
- 1/3/5-round weak drills and a 500-answer starvation simulation;
- stable correctness after option shuffling;
- 25 unique mock questions, 20/25 pass threshold, early finish, and unanswered accounting;
- notes, bookmarks, concepts, personal glossary, backup round trip, and rejection of category-2 backups;
- exact 218-number bank, source provenance, 127 referenced glossary entries, topic reference behavior, 11 required question-to-figure mappings, and 654 wrong-option explanations;
- clean source-checked option text for figure questions 23 and 32.

Content checks independently require 218 authored records, 0 fallback, 215 exact + 3 explicit manual answer matches, 0 fuzzy matches, valid source PDF hashes, and a complete answer-free figure manifest.

Latest local result: **54/54 tests**, **218 questions**, **127 runtime terms**, **4 shared exam assets for 11 questions**, **0 fuzzy matches**. Release build, ad-hoc signature, bundle identity, and screenshots are checked separately.

# Architecture

HAM Trainer 3 is a fully local native SwiftUI macOS application with no networking layer.

## Boundaries

- `CategoryProfile` is the single product contract: identity, exact 218-number set, mock 25/20, data directory, and backup identity.
- `Content/` is immutable runtime study material bundled with the application.
- `AdaptiveReviewScheduler` owns deterministic eligibility and queue composition; `StudySession` owns same-session delayed repeats and immutable attempt history.
- `AppStore` is the main-actor persistence boundary and atomically saves question/concept progress, notes, glossary, settings, and mock history.
- SwiftUI views consume `AppStore` through the environment and never modify content JSON.

Stable question and option IDs keep progress valid when presentation order changes. Correctness never depends on a displayed letter or index.

## Main flows

Smart Study selects due/weak/new questions and recalculates after each answer. Topic reference pages show every official answer without recording progress and expose one explicit training action. The global question browser uses local in-memory search and compact state filters. Mock Exam samples 25 unique questions, hides explanations until completion, applies the 20/25 threshold, and records only submitted answers.

## Persistence and isolation

Schema version 3 lives at `Application Support/HAMTrainer3/progress-v1.json`. Backups include product identity `HAMTrainer3`; a category-2 or identity-less backup is rejected before state mutation. This prevents accidental reuse of the original HAM Trainer progress.

## Platform

The target is macOS 14+ with SwiftUI, AppKit panels, Foundation Codable/FileManager, and no third-party runtime libraries. The SwiftPM build creates `HAM Trainer 3.app` with bundle identifier `local.hamtrainer3.app` and executable `HAMTrainer3`.

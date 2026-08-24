import Foundation

struct QuestionOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let text: String
}

struct SourceReference: Codable, Hashable, Sendable {
    let document: String
    let page: Int
    let sourceQuestionNumber: Int
    let explanationDocument: String
    let explanationPage: Int
}

struct Question: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let examNumber: Int
    let stem: String
    let options: [QuestionOption]
    let correctOptionId: String
    let officialCorrectAnswerText: String
    let topic: String
    let subtopic: String
    let type: String
    let explanationShort: String
    let explanationBeginner: String
    let explanationReasoning: String
    let wrongOptionExplanations: [String: String]
    let memoryHint: String
    let glossaryTerms: [String]
    let figureAsset: String?
    var useExamFigure: Bool = false
    var sourceExtractionNote: String?
    var teachingDiagramAsset: String?
    let sourceReference: SourceReference
    let legalHistoricalNote: String?
}

extension Question {
    func matchesReferenceQuery(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return "\(examNumber) \(stem) \(officialCorrectAnswerText) \(explanationShort)"
            .localizedCaseInsensitiveContains(query)
    }
}

struct GlossaryEntry: Hashable, Identifiable, Sendable {
    let id: String
    let term: String
    let aliases: [String]
    let shortDefinition: String
    let fromZero: String
    let radioExample: String
    var relatedTerms: [String] = []
    var diagramAsset: String?
}

extension GlossaryEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, term, aliases, shortDefinition, fromZero, radioExample, relatedTerms, diagramAsset
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        term = try values.decode(String.self, forKey: .term)
        aliases = try values.decodeIfPresent([String].self, forKey: .aliases) ?? []
        shortDefinition = try values.decode(String.self, forKey: .shortDefinition)
        fromZero = try values.decode(String.self, forKey: .fromZero)
        radioExample = try values.decode(String.self, forKey: .radioExample)
        relatedTerms = try values.decodeIfPresent([String].self, forKey: .relatedTerms) ?? []
        diagramAsset = try values.decodeIfPresent(String.self, forKey: .diagramAsset)
    }
}

struct PersonalGlossaryEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var term: String
    var shortDefinition: String
    var detailedExplanation: String
    var personalNotes: String
    var example: String
    var relatedQuestionIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), term: String, shortDefinition: String = "",
        detailedExplanation: String = "", personalNotes: String = "",
        example: String = "", relatedQuestionIDs: [String] = [],
        createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.shortDefinition = shortDefinition
        self.detailedExplanation = detailedExplanation
        self.personalNotes = personalNotes
        self.example = example
        self.relatedQuestionIDs = relatedQuestionIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum LearningState: String, Codable, CaseIterable, Sendable {
    case unseen, learning, review, mastered, weak

    var title: String {
        switch self {
        case .unseen: "Не изучен"
        case .learning: "Изучение"
        case .review: "Повторение"
        case .mastered: "Освоен"
        case .weak: "Слабый"
        }
    }
}

enum AttemptOutcome: String, Codable, Sendable {
    case correct, incorrect, dontKnow, revealedBeforeAnswer
    var isFailure: Bool { self != .correct }
}

enum StudySelectionReason: String, Codable, CaseIterable, Sendable {
    case new, weak, due, lapse, maintenance, manuallySelected, sessionMistake
}

enum WeakQuestionFilter: String, CaseIterable, Identifiable, Sendable {
    case all, recent, dontKnow, historicalErrors, hard
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все слабые"
        case .recent: "Недавние ошибки"
        case .dontKnow: "Не знаю"
        case .historicalErrors: "Были ошибки"
        case .hard: "Отмечены сложными"
        }
    }

    func matches(_ progress: QuestionProgress, now: Date = Date()) -> Bool {
        switch self {
        case .all: progress.state == .weak || progress.manuallyMarkedHard
        case .recent:
            progress.lastFailureAt.map { $0 >= now.addingTimeInterval(-7 * 24 * 60 * 60) } ?? false
        case .dontKnow: progress.dontKnowCount > 0
        case .historicalErrors: progress.incorrectCount > 0
        case .hard: progress.manuallyMarkedHard
        }
    }
}

struct StudyCard: Identifiable, Hashable, Sendable {
    let question: Question
    let reason: StudySelectionReason
    var id: String { question.id }
}

enum MistakeReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case unknownTerm = "Не знал термин"
    case forgotFact = "Забыл факт"
    case missedPrinciple = "Не понял принцип"
    case calculation = "Ошибка в расчёте"
    case misread = "Невнимательно прочитал"
    case guessed = "Угадал"
    var id: String { rawValue }
}

struct QuestionProgress: Hashable, Sendable {
    var questionId: String
    var state: LearningState = .unseen
    var attempts = 0
    var correctCount = 0
    var incorrectCount = 0
    var dontKnowCount = 0
    var revealedCount = 0
    var consecutiveCorrect = 0
    var successfulSpacedReviews = 0
    var lapseCount = 0
    var reviewStage = 0
    var lastSeenStudyStep: Int?
    var nextDueStudyStep: Int?
    var lastSelectionReason: StudySelectionReason?
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var lastFailureAt: Date?
    var lastOutcome: AttemptOutcome?
    var bookmarked = false
    var manuallyMarkedHard = false
    var note = ""
    var lastMistakeReason: MistakeReason?

    init(questionId: String) { self.questionId = questionId }
}

extension QuestionProgress: Codable {
    private enum CodingKeys: String, CodingKey {
        case questionId, state, attempts, correctCount, incorrectCount, dontKnowCount, revealedCount
        case consecutiveCorrect, successfulSpacedReviews, lapseCount, reviewStage
        case lastSeenStudyStep, nextDueStudyStep, lastSelectionReason
        case firstSeenAt, lastSeenAt, lastFailureAt, lastOutcome
        case bookmarked, manuallyMarkedHard, note, lastMistakeReason
        case nextDueAt, intervalDays
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        questionId = try values.decode(String.self, forKey: .questionId)
        state = try values.decodeIfPresent(LearningState.self, forKey: .state) ?? .unseen
        attempts = try values.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        correctCount = try values.decodeIfPresent(Int.self, forKey: .correctCount) ?? 0
        incorrectCount = try values.decodeIfPresent(Int.self, forKey: .incorrectCount) ?? 0
        dontKnowCount = try values.decodeIfPresent(Int.self, forKey: .dontKnowCount) ?? 0
        revealedCount = try values.decodeIfPresent(Int.self, forKey: .revealedCount) ?? 0
        consecutiveCorrect = try values.decodeIfPresent(Int.self, forKey: .consecutiveCorrect) ?? 0
        successfulSpacedReviews = try values.decodeIfPresent(Int.self, forKey: .successfulSpacedReviews) ?? 0
        lapseCount = try values.decodeIfPresent(Int.self, forKey: .lapseCount) ?? 0
        reviewStage = try values.decodeIfPresent(Int.self, forKey: .reviewStage) ?? 0
        lastSeenStudyStep = try values.decodeIfPresent(Int.self, forKey: .lastSeenStudyStep)
        nextDueStudyStep = try values.decodeIfPresent(Int.self, forKey: .nextDueStudyStep)
        lastSelectionReason = try values.decodeIfPresent(StudySelectionReason.self, forKey: .lastSelectionReason)
        firstSeenAt = try values.decodeIfPresent(Date.self, forKey: .firstSeenAt)
        lastSeenAt = try values.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        lastFailureAt = try values.decodeIfPresent(Date.self, forKey: .lastFailureAt)
        lastOutcome = try values.decodeIfPresent(AttemptOutcome.self, forKey: .lastOutcome)
        bookmarked = try values.decodeIfPresent(Bool.self, forKey: .bookmarked) ?? false
        manuallyMarkedHard = try values.decodeIfPresent(Bool.self, forKey: .manuallyMarkedHard) ?? false
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        lastMistakeReason = try values.decodeIfPresent(MistakeReason.self, forKey: .lastMistakeReason)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(questionId, forKey: .questionId)
        try values.encode(state, forKey: .state)
        try values.encode(attempts, forKey: .attempts)
        try values.encode(correctCount, forKey: .correctCount)
        try values.encode(incorrectCount, forKey: .incorrectCount)
        try values.encode(dontKnowCount, forKey: .dontKnowCount)
        try values.encode(revealedCount, forKey: .revealedCount)
        try values.encode(consecutiveCorrect, forKey: .consecutiveCorrect)
        try values.encode(successfulSpacedReviews, forKey: .successfulSpacedReviews)
        try values.encode(lapseCount, forKey: .lapseCount)
        try values.encode(reviewStage, forKey: .reviewStage)
        try values.encodeIfPresent(lastSeenStudyStep, forKey: .lastSeenStudyStep)
        try values.encodeIfPresent(nextDueStudyStep, forKey: .nextDueStudyStep)
        try values.encodeIfPresent(lastSelectionReason, forKey: .lastSelectionReason)
        try values.encodeIfPresent(firstSeenAt, forKey: .firstSeenAt)
        try values.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try values.encodeIfPresent(lastFailureAt, forKey: .lastFailureAt)
        try values.encodeIfPresent(lastOutcome, forKey: .lastOutcome)
        try values.encode(bookmarked, forKey: .bookmarked)
        try values.encode(manuallyMarkedHard, forKey: .manuallyMarkedHard)
        try values.encode(note, forKey: .note)
        try values.encodeIfPresent(lastMistakeReason, forKey: .lastMistakeReason)
    }
}

struct ConceptProgress: Codable, Hashable, Sendable {
    var conceptId: String
    var unclearCount = 0
    var understoodCount = 0
    var isLearned = false
    var personalNotes = ""
    var lastReviewedAt: Date?
    init(conceptId: String) { self.conceptId = conceptId }
}

struct MockExamScore: Hashable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let correct: Int
    let answered: Int
    let incorrect: Int
    let unanswered: Int
    let total: Int
    var passed: Bool { correct >= CategoryProfile.passingScore }
}

extension MockExamScore: Codable {
    private enum CodingKeys: String, CodingKey { case id, date, correct, answered, incorrect, unanswered, total }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        correct = try values.decode(Int.self, forKey: .correct)
        total = try values.decodeIfPresent(Int.self, forKey: .total) ?? CategoryProfile.examQuestionCount
        answered = try values.decodeIfPresent(Int.self, forKey: .answered) ?? total
        incorrect = try values.decodeIfPresent(Int.self, forKey: .incorrect) ?? max(0, answered - correct)
        unanswered = try values.decodeIfPresent(Int.self, forKey: .unanswered) ?? max(0, total - answered)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(date, forKey: .date)
        try values.encode(correct, forKey: .correct)
        try values.encode(answered, forKey: .answered)
        try values.encode(incorrect, forKey: .incorrect)
        try values.encode(unanswered, forKey: .unanswered)
        try values.encode(total, forKey: .total)
    }
}

enum ReadingSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular = "Обычный"
    case large = "Крупный"
    case extraLarge = "Очень крупный"
    var id: String { rawValue }
}

struct UserSettings: Hashable, Sendable {
    var defaultSessionLength = 20
    var randomizeOptions = true
    var explanationStyle = "С нуля"
    var readingSize: ReadingSize = .large
}

extension UserSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case defaultSessionLength, randomizeOptions, explanationStyle, readingSize
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultSessionLength = try values.decodeIfPresent(Int.self, forKey: .defaultSessionLength) ?? 20
        randomizeOptions = try values.decodeIfPresent(Bool.self, forKey: .randomizeOptions) ?? true
        explanationStyle = try values.decodeIfPresent(String.self, forKey: .explanationStyle) ?? "С нуля"
        readingSize = try values.decodeIfPresent(ReadingSize.self, forKey: .readingSize) ?? .large
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(defaultSessionLength, forKey: .defaultSessionLength)
        try values.encode(randomizeOptions, forKey: .randomizeOptions)
        try values.encode(explanationStyle, forKey: .explanationStyle)
        try values.encode(readingSize, forKey: .readingSize)
    }
}

struct ProgressBackup: Sendable {
    var schemaVersion: Int
    var productIdentity: String
    var exportedAt: Date
    var studyStep: Int
    var progress: [String: QuestionProgress]
    var conceptProgress: [String: ConceptProgress]
    var personalGlossary: [PersonalGlossaryEntry]
    var mockScores: [MockExamScore]
    var settings: UserSettings
}

extension ProgressBackup: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, productIdentity, exportedAt, studyStep, progress, conceptProgress, personalGlossary
        case weakConceptIds, mockScores, settings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        productIdentity = try values.decodeIfPresent(String.self, forKey: .productIdentity) ?? ""
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        studyStep = try values.decodeIfPresent(Int.self, forKey: .studyStep) ?? 0
        progress = try values.decodeIfPresent([String: QuestionProgress].self, forKey: .progress) ?? [:]
        conceptProgress = try values.decodeIfPresent([String: ConceptProgress].self, forKey: .conceptProgress) ?? [:]
        if conceptProgress.isEmpty {
            let legacy = try values.decodeIfPresent(Set<String>.self, forKey: .weakConceptIds) ?? []
            conceptProgress = Dictionary(uniqueKeysWithValues: legacy.map { id in
                var item = ConceptProgress(conceptId: id)
                item.unclearCount = 1
                return (id, item)
            })
        }
        personalGlossary = try values.decodeIfPresent([PersonalGlossaryEntry].self, forKey: .personalGlossary) ?? []
        mockScores = try values.decodeIfPresent([MockExamScore].self, forKey: .mockScores) ?? []
        settings = try values.decodeIfPresent(UserSettings.self, forKey: .settings) ?? UserSettings()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(productIdentity, forKey: .productIdentity)
        try values.encode(exportedAt, forKey: .exportedAt)
        try values.encode(studyStep, forKey: .studyStep)
        try values.encode(progress, forKey: .progress)
        try values.encode(conceptProgress, forKey: .conceptProgress)
        try values.encode(personalGlossary, forKey: .personalGlossary)
        try values.encode(mockScores, forKey: .mockScores)
        try values.encode(settings, forKey: .settings)
    }
}

struct SessionAttempt: Hashable, Sendable {
    let questionId: String
    let outcome: AttemptOutcome
    let previousState: LearningState
    let newState: LearningState
}

struct SessionSummary: Sendable {
    var attempts: [SessionAttempt] = []
    var total = 0
    var correct = 0
    var incorrect = 0
    var dontKnow = 0
    var revealed = 0
    var becameWeak = 0
    var improved = 0
    var mastered = 0
    var topics: [String: Int] = [:]
    var unclearConceptIDs: [String] = []

    var mistakeQuestionIDs: [String] {
        var seen = Set<String>()
        return attempts.compactMap { attempt in
            guard attempt.outcome.isFailure, seen.insert(attempt.questionId).inserted else { return nil }
            return attempt.questionId
        }
    }
}

import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let schemaVersion = 3

    @Published private(set) var questions: [Question] = []
    @Published private(set) var glossary: [GlossaryEntry] = []
    @Published var studyStep = 0
    @Published var progress: [String: QuestionProgress] = [:]
    @Published var conceptProgress: [String: ConceptProgress] = [:]
    @Published var personalGlossary: [PersonalGlossaryEntry] = []
    @Published var mockScores: [MockExamScore] = []
    @Published var settings = UserSettings()
    @Published var errorMessage: String?

    private let scheduler = AdaptiveReviewScheduler()
    private let persistenceURL: URL

    init(persistenceURL: URL? = nil, loadContent: Bool = true) {
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL
        if loadContent { loadBundledContent() }
        loadProgress()
    }

    static var defaultPersistenceURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent(CategoryProfile.persistenceNamespace, isDirectory: true).appendingPathComponent("progress-v1.json")
    }

    var weakConceptIds: Set<String> {
        Set(conceptProgress.values.filter { !$0.isLearned && $0.unclearCount > 0 }.map(\.conceptId))
    }

    func progressFor(_ question: Question) -> QuestionProgress {
        progress[question.id] ?? QuestionProgress(questionId: question.id)
    }

    func conceptProgressFor(_ id: String) -> ConceptProgress {
        conceptProgress[id] ?? ConceptProgress(conceptId: id)
    }

    @discardableResult
    func record(
        _ outcome: AttemptOutcome,
        for question: Question,
        reason: StudySelectionReason? = nil,
        at date: Date = Date()
    ) -> QuestionProgress {
        studyStep += 1
        let updated = scheduler.applying(
            outcome,
            to: progressFor(question),
            completedStudyStep: studyStep,
            selectionReason: reason,
            at: date
        )
        progress[question.id] = updated
        saveProgress()
        return updated
    }

    func toggleBookmark(_ question: Question) {
        var item = progressFor(question)
        item.bookmarked.toggle()
        progress[question.id] = item
        saveProgress()
    }

    func toggleHard(_ question: Question) {
        var item = progressFor(question)
        item.manuallyMarkedHard.toggle()
        if item.manuallyMarkedHard && item.state != .mastered { item.state = .weak }
        progress[question.id] = item
        saveProgress()
    }

    func updateNote(_ note: String, for question: Question) {
        var item = progressFor(question)
        item.note = note
        progress[question.id] = item
        saveProgress()
    }

    func markConceptWeak(_ id: String) {
        var item = conceptProgressFor(id)
        item.unclearCount += 1
        item.isLearned = false
        item.lastReviewedAt = Date()
        conceptProgress[id] = item
        saveProgress()
    }

    func markConceptUnderstood(_ id: String) {
        var item = conceptProgressFor(id)
        item.understoodCount += 1
        item.isLearned = true
        item.lastReviewedAt = Date()
        conceptProgress[id] = item
        saveProgress()
    }

    func updateConceptNote(_ note: String, id: String) {
        var item = conceptProgressFor(id)
        item.personalNotes = note
        conceptProgress[id] = item
        saveProgress()
    }

    @discardableResult
    func addPersonalGlossaryEntry(term: String, relatedQuestionIDs: [String] = []) -> PersonalGlossaryEntry {
        let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return PersonalGlossaryEntry(term: "") }
        let entry = PersonalGlossaryEntry(term: cleaned, relatedQuestionIDs: validatedQuestionIDs(relatedQuestionIDs))
        personalGlossary.append(entry)
        saveProgress()
        return entry
    }

    func updatePersonalGlossaryEntry(_ entry: PersonalGlossaryEntry) {
        guard let index = personalGlossary.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.term.isEmpty else { return }
        updated.relatedQuestionIDs = validatedQuestionIDs(entry.relatedQuestionIDs)
        updated.updatedAt = Date()
        personalGlossary[index] = updated
        saveProgress()
    }

    func deletePersonalGlossaryEntry(id: UUID) {
        personalGlossary.removeAll { $0.id == id }
        saveProgress()
    }

    private func validatedQuestionIDs(_ ids: [String]) -> [String] {
        guard !questions.isEmpty else { return Array(Set(ids)).sorted() }
        return Self.validatedQuestionIDs(ids, validQuestionIDs: Set(questions.map(\.id)))
    }

    static func validatedQuestionIDs(_ ids: [String], validQuestionIDs: Set<String>) -> [String] {
        Array(Set(ids).intersection(validQuestionIDs)).sorted()
    }

    func tagMistake(_ reason: MistakeReason, question: Question) {
        var item = progressFor(question)
        item.lastMistakeReason = reason
        progress[question.id] = item
        saveProgress()
    }

    func smartCards(length: Int) -> [StudyCard] {
        scheduler.smartQueue(questions: questions, progress: progress, length: length, completedStudyStep: studyStep)
    }

    func isDue(_ question: Question) -> Bool {
        scheduler.isDue(progressFor(question), completedStudyStep: studyStep)
    }

    func remainingQuestionDistance(for question: Question) -> Int? {
        scheduler.remainingQuestionDistance(progressFor(question), completedStudyStep: studyStep)
    }

    func smartQuestions(length: Int) -> [Question] {
        smartCards(length: length).map(\.question)
    }

    func questions(for ids: [String]) -> [Question] {
        let byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    @discardableResult
    func finishMockExam(questions examQuestions: [Question], answers: [String: String], at date: Date = Date()) -> MockExamResult {
        let result = MockExamBuilder().grade(questions: examQuestions, answers: answers)
        let correctIDs = Set(result.correctQuestionIDs)
        let incorrectIDs = Set(result.incorrectQuestionIDs)

        for question in examQuestions where correctIDs.contains(question.id) || incorrectIDs.contains(question.id) {
            studyStep += 1
            let outcome: AttemptOutcome = correctIDs.contains(question.id) ? .correct : .incorrect
            progress[question.id] = scheduler.applying(
                outcome,
                to: progressFor(question),
                completedStudyStep: studyStep,
                selectionReason: .manuallySelected,
                at: date
            )
        }
        mockScores.append(MockExamScore(
            id: UUID(), date: date, correct: result.correct, answered: result.answered,
            incorrect: result.incorrectQuestionIDs.count, unanswered: result.unansweredQuestionIDs.count,
            total: examQuestions.count
        ))
        saveProgress()
        return result
    }

    func exportBackup(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(currentBackup()).write(to: url, options: .atomic)
    }

    func importBackup(from url: URL) throws {
        var backup = try Self.decoder.decode(ProgressBackup.self, from: Data(contentsOf: url))
        guard backup.schemaVersion <= Self.schemaVersion,
              backup.productIdentity == CategoryProfile.persistenceNamespace,
              backup.studyStep >= 0 else {
            throw CocoaError(.coderReadCorrupt)
        }
        backup = migrate(backup)
        guard backup.personalGlossary.allSatisfy({ !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw CocoaError(.coderReadCorrupt)
        }

        let validQuestionIDs = Set(questions.map(\.id))
        let importedProgress = questions.isEmpty ? backup.progress : backup.progress.filter { validQuestionIDs.contains($0.key) }
        let importedGlossary = backup.personalGlossary.map { entry -> PersonalGlossaryEntry in
            var value = entry
            value.relatedQuestionIDs = entry.relatedQuestionIDs.filter { validQuestionIDs.contains($0) }
            return value
        }

        studyStep = backup.studyStep
        progress = importedProgress
        conceptProgress = backup.conceptProgress
        personalGlossary = importedGlossary
        mockScores = backup.mockScores
        settings = backup.settings
        saveProgress()
    }

    func resetProgress() {
        studyStep = 0
        progress = [:]
        conceptProgress = [:]
        personalGlossary = []
        mockScores = []
        saveProgress()
    }

    func saveProgress() {
        do {
            try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(currentBackup()).write(to: persistenceURL, options: .atomic)
        } catch {
            errorMessage = "Не удалось сохранить прогресс: \(error.localizedDescription)"
        }
    }

    private func currentBackup() -> ProgressBackup {
        ProgressBackup(
            schemaVersion: Self.schemaVersion,
            productIdentity: CategoryProfile.persistenceNamespace,
            exportedAt: Date(),
            studyStep: studyStep,
            progress: progress,
            conceptProgress: conceptProgress,
            personalGlossary: personalGlossary,
            mockScores: mockScores,
            settings: settings
        )
    }

    private func loadBundledContent() {
        do {
            let questionsURL = try resourceURL("questions.json")
            let glossaryURL = try resourceURL("glossary.json")
            questions = try Self.decoder.decode([Question].self, from: Data(contentsOf: questionsURL))
            glossary = try Self.decoder.decode([GlossaryEntry].self, from: Data(contentsOf: glossaryURL))
            guard questions.count == CategoryProfile.bankCount,
                  Set(questions.map(\.examNumber)) == CategoryProfile.examNumbers else {
                throw CocoaError(.coderReadCorrupt)
            }
        } catch {
            errorMessage = "Не удалось загрузить банк вопросов: \(error.localizedDescription)"
        }
    }

    private func resourceURL(_ name: String) throws -> URL {
        if let url = Bundle.studyResources.url(forResource: name, withExtension: nil, subdirectory: "Content") { return url }
        throw CocoaError(.fileNoSuchFile)
    }

    private func loadProgress() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            var backup = try Self.decoder.decode(ProgressBackup.self, from: Data(contentsOf: persistenceURL))
            guard backup.schemaVersion <= Self.schemaVersion,
                  backup.productIdentity == CategoryProfile.persistenceNamespace else {
                throw CocoaError(.coderReadCorrupt)
            }
            backup = migrate(backup)
            studyStep = backup.studyStep
            progress = backup.progress
            conceptProgress = backup.conceptProgress
            personalGlossary = backup.personalGlossary
            mockScores = backup.mockScores
            settings = backup.settings
            if backup.schemaVersion != Self.schemaVersion { saveProgress() }
        } catch {
            errorMessage = "Файл прогресса повреждён. Исходный файл сохранён: \(error.localizedDescription)"
        }
    }

    private func migrate(_ source: ProgressBackup) -> ProgressBackup {
        guard source.schemaVersion < Self.schemaVersion else { return source }
        var migrated = source
        migrated.schemaVersion = Self.schemaVersion
        migrated.productIdentity = CategoryProfile.persistenceNamespace
        migrated.studyStep = max(source.studyStep, source.progress.values.reduce(0) { $0 + $1.attempts })
        for (id, old) in source.progress {
            var item = old
            guard item.state != .unseen else { continue }
            switch item.state {
            case .mastered:
                item.reviewStage = AdaptiveReviewScheduler.questionIntervals.count - 1
                item.nextDueStudyStep = migrated.studyStep + AdaptiveReviewScheduler.questionIntervals.last! + 1
            case .weak, .learning:
                item.reviewStage = 0
                item.nextDueStudyStep = migrated.studyStep + 1
            case .review:
                item.reviewStage = min(max(1, item.successfulSpacedReviews), AdaptiveReviewScheduler.questionIntervals.count - 1)
                item.nextDueStudyStep = migrated.studyStep + 1
            case .unseen:
                break
            }
            migrated.progress[id] = item
        }
        return migrated
    }

    static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}

extension Bundle {
    static var studyResources: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}

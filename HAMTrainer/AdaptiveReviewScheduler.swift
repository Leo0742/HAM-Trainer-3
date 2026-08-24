import Foundation

struct AdaptiveReviewScheduler: Sendable {
    static let questionIntervals = [5, 10, 20, 40, 80]
    static let minimumOtherQuestionGap = 5

    func applying(
        _ outcome: AttemptOutcome,
        to old: QuestionProgress,
        completedStudyStep: Int,
        selectionReason: StudySelectionReason? = nil,
        at now: Date = Date()
    ) -> QuestionProgress {
        precondition(completedStudyStep > 0)
        var progress = old
        progress.attempts += 1
        progress.firstSeenAt = progress.firstSeenAt ?? now
        progress.lastSeenAt = now
        progress.lastSeenStudyStep = completedStudyStep
        progress.lastOutcome = outcome
        progress.lastSelectionReason = selectionReason

        switch outcome {
        case .correct:
            progress.correctCount += 1
            progress.consecutiveCorrect += 1
            let isFirstLearningAnswer = old.state == .unseen
            let isDueSpacedReview = old.nextDueStudyStep.map { completedStudyStep >= $0 } ?? false

            if isFirstLearningAnswer {
                progress.reviewStage = 0
                progress.nextDueStudyStep = completedStudyStep + Self.questionIntervals[0] + 1
                progress.state = .review
            } else if isDueSpacedReview {
                progress.successfulSpacedReviews += 1
                progress.reviewStage = min(old.reviewStage + 1, Self.questionIntervals.count - 1)
                let interval = Self.questionIntervals[progress.reviewStage]
                progress.nextDueStudyStep = completedStudyStep + interval + 1

                if progress.reviewStage == Self.questionIntervals.count - 1,
                   progress.successfulSpacedReviews >= 4 {
                    progress.state = .mastered
                } else if old.state == .weak && progress.consecutiveCorrect < 2 {
                    progress.state = .weak
                } else {
                    progress.state = .review
                }
            } else {
                // This answer is useful practice, but it is not a spaced review.
                // Moving the due step by one prevents rapid repeats of this same
                // question from counting as one of the required OTHER answers.
                progress.reviewStage = old.reviewStage
                progress.successfulSpacedReviews = old.successfulSpacedReviews
                progress.nextDueStudyStep = old.nextDueStudyStep.map { $0 + 1 }
                progress.state = old.state
            }

        case .incorrect, .dontKnow, .revealedBeforeAnswer:
            if outcome == .incorrect { progress.incorrectCount += 1 }
            if outcome == .dontKnow { progress.dontKnowCount += 1 }
            if outcome == .revealedBeforeAnswer { progress.revealedCount += 1 }
            progress.consecutiveCorrect = 0
            if old.state != .unseen { progress.lapseCount += 1 }
            progress.lastFailureAt = now
            progress.reviewStage = 0
            progress.nextDueStudyStep = completedStudyStep + Self.minimumOtherQuestionGap + 1
            progress.state = outcome == .incorrect && old.state == .unseen ? .learning : .weak
        }
        return progress
    }

    func isDue(_ progress: QuestionProgress, completedStudyStep: Int) -> Bool {
        guard progress.state != .unseen, let due = progress.nextDueStudyStep else { return false }
        return completedStudyStep + 1 >= due
    }

    func remainingQuestionDistance(_ progress: QuestionProgress, completedStudyStep: Int) -> Int? {
        guard let due = progress.nextDueStudyStep else { return nil }
        return max(0, due - (completedStudyStep + 1))
    }

    func selectionReason(for progress: QuestionProgress, completedStudyStep: Int) -> StudySelectionReason? {
        if progress.state == .unseen { return .new }
        guard isDue(progress, completedStudyStep: completedStudyStep) else { return nil }
        if progress.state == .mastered { return .maintenance }
        if progress.lapseCount > 0 && progress.lastOutcome?.isFailure == true { return .lapse }
        if progress.state == .weak || progress.state == .learning { return .weak }
        return .due
    }

    func smartQueue(
        questions: [Question],
        progress: [String: QuestionProgress],
        length: Int,
        completedStudyStep: Int
    ) -> [StudyCard] {
        let requested = max(1, min(length, questions.count))
        let getProgress = { (question: Question) in
            progress[question.id] ?? QuestionProgress(questionId: question.id)
        }
        let classified = questions.compactMap { question -> StudyCard? in
            guard let reason = selectionReason(for: getProgress(question), completedStudyStep: completedStudyStep) else { return nil }
            return StudyCard(question: question, reason: reason)
        }

        let orderedReasons: [StudySelectionReason] = [.lapse, .weak, .due, .new]
        var result: [StudyCard] = []
        for reason in orderedReasons {
            let candidates = classified.filter { $0.reason == reason }.sorted {
                priority($0, progress: getProgress($0.question), completedStudyStep: completedStudyStep) >
                priority($1, progress: getProgress($1.question), completedStudyStep: completedStudyStep)
            }
            appendBalanced(from: candidates, to: &result, limit: requested)
        }

        let maintenanceLimit = min(max(1, requested / 10), requested - result.count)
        if maintenanceLimit > 0 {
            let maintenance = classified.filter { $0.reason == .maintenance }.sorted {
                let left = getProgress($0.question).nextDueStudyStep ?? .max
                let right = getProgress($1.question).nextDueStudyStep ?? .max
                return left == right ? $0.question.examNumber < $1.question.examNumber : left < right
            }
            appendBalanced(from: Array(maintenance.prefix(maintenanceLimit)), to: &result, limit: requested)
        }
        return result
    }

    private func priority(_ card: StudyCard, progress: QuestionProgress, completedStudyStep: Int) -> Double {
        let overdue = Double(max(0, completedStudyStep + 1 - (progress.nextDueStudyStep ?? completedStudyStep + 1)))
        let reasonWeight: Double = switch card.reason {
        case .lapse: 600
        case .weak: 500
        case .due: 400
        case .new: 300
        case .maintenance: 100
        case .manuallySelected, .sessionMistake: 0
        }
        return reasonWeight + overdue + Double(progress.lapseCount) * 0.1 - Double(card.question.examNumber) / 10_000
    }

    private func appendBalanced(from candidates: [StudyCard], to result: inout [StudyCard], limit: Int) {
        guard result.count < limit else { return }
        let maxPerTopic = max(1, Int(ceil(Double(limit) * 0.4)))
        var deferred: [StudyCard] = []
        for card in candidates where result.count < limit && !result.contains(where: { $0.id == card.id }) {
            if result.filter({ $0.question.topic == card.question.topic }).count < maxPerTopic {
                result.append(card)
            } else {
                deferred.append(card)
            }
        }
        for card in deferred where result.count < limit && !result.contains(where: { $0.id == card.id }) {
            result.append(card)
        }
    }
}

struct StudyOccurrence: Identifiable, Hashable, Sendable {
    let id: UUID
    let card: StudyCard
    let displayedOptions: [QuestionOption]
    var selectedOptionId: String?
    var outcome: AttemptOutcome?
    let round: Int?

    init(card: StudyCard, randomizeOptions: Bool, round: Int? = nil) {
        id = UUID()
        self.card = card
        displayedOptions = randomizeOptions ? card.question.options.shuffled() : card.question.options
        self.round = round
    }
}

struct StudySession: Sendable {
    private(set) var occurrences: [StudyOccurrence]
    private(set) var index = 0
    private(set) var viewingIndex = 0
    private(set) var appearanceCounts: [String: Int] = [:]
    private(set) var summary = SessionSummary()
    let drillWeak: Bool
    let dynamicallyReconsidersSmartQueue: Bool
    let totalRounds: Int
    private let randomizeOptions: Bool
    private let isFixedRoundDrill: Bool
    private let targetAnswerCount: Int

    init(
        cards: [StudyCard], drillWeak: Bool = false,
        dynamicallyReconsidersSmartQueue: Bool = false,
        randomizeOptions: Bool = true
    ) {
        occurrences = cards.map { StudyOccurrence(card: $0, randomizeOptions: randomizeOptions) }
        self.drillWeak = drillWeak
        self.dynamicallyReconsidersSmartQueue = dynamicallyReconsidersSmartQueue
        self.randomizeOptions = randomizeOptions
        totalRounds = 1
        isFixedRoundDrill = false
        targetAnswerCount = cards.count
    }

    init(
        questions: [Question], reason: StudySelectionReason = .manuallySelected,
        drillWeak: Bool = false, randomizeOptions: Bool = true
    ) {
        self.init(
            cards: questions.map { StudyCard(question: $0, reason: reason) },
            drillWeak: drillWeak,
            randomizeOptions: randomizeOptions
        )
    }

    init(
        intensiveQuestions questions: [Question], rounds: Int,
        randomizeOptions: Bool = true,
        shuffle: ([Question]) -> [Question] = { $0.shuffled() }
    ) {
        let safeRounds = [1, 3, 5].contains(rounds) ? rounds : 1
        var built: [StudyOccurrence] = []
        for round in 1...safeRounds {
            var ordered = shuffle(questions)
            if questions.count > 1, let previous = built.last?.card.question.id,
               ordered.first?.id == previous,
               let swapIndex = ordered.firstIndex(where: { $0.id != previous }) {
                ordered.swapAt(0, swapIndex)
            }
            built.append(contentsOf: ordered.map {
                StudyOccurrence(
                    card: StudyCard(question: $0, reason: .manuallySelected),
                    randomizeOptions: randomizeOptions,
                    round: round
                )
            })
        }
        occurrences = built
        drillWeak = true
        dynamicallyReconsidersSmartQueue = false
        self.randomizeOptions = randomizeOptions
        totalRounds = safeRounds
        isFixedRoundDrill = true
        targetAnswerCount = built.count
    }

    var queue: [StudyCard] { occurrences.map(\.card) }
    var currentOccurrence: StudyOccurrence? { viewingIndex < occurrences.count ? occurrences[viewingIndex] : nil }
    var current: StudyCard? { currentOccurrence?.card }
    var currentQuestion: Question? { current?.question }
    var isComplete: Bool { index >= occurrences.count }
    var position: Int { min(viewingIndex + 1, occurrences.count) }
    var currentRound: Int { currentOccurrence?.round ?? 1 }
    var canGoBack: Bool { viewingIndex > 0 }
    var canGoForward: Bool { viewingIndex < index }
    var isViewingHistory: Bool { viewingIndex < index }
    var smartRefreshLength: Int { max(0, targetAnswerCount - index) }

    mutating func record(
        _ outcome: AttemptOutcome, selectedOptionId: String? = nil,
        previousState: LearningState, newState: LearningState
    ) {
        guard viewingIndex == index, occurrences.indices.contains(index), occurrences[index].outcome == nil else { return }
        occurrences[index].selectedOptionId = selectedOptionId
        occurrences[index].outcome = outcome
        let card = occurrences[index].card
        let question = card.question
        let count = appearanceCounts[question.id, default: 0] + 1
        appearanceCounts[question.id] = count
        summary.attempts.append(SessionAttempt(questionId: question.id, outcome: outcome, previousState: previousState, newState: newState))
        summary.total += 1
        switch outcome {
        case .correct: summary.correct += 1
        case .incorrect: summary.incorrect += 1
        case .dontKnow: summary.dontKnow += 1
        case .revealedBeforeAnswer: summary.revealed += 1
        }
        if previousState != .weak && newState == .weak { summary.becameWeak += 1 }
        if (previousState == .weak || previousState == .learning) && newState == .review { summary.improved += 1 }
        if previousState != .mastered && newState == .mastered { summary.mastered += 1 }

        if outcome.isFailure {
            summary.topics[question.topic, default: 0] += 1
            let appearanceLimit = drillWeak ? 3 : 2
            let insertion = index + AdaptiveReviewScheduler.minimumOtherQuestionGap + 1
            if !isFixedRoundDrill, count < appearanceLimit, insertion <= occurrences.count {
                let repeatOccurrence = StudyOccurrence(
                    card: StudyCard(question: question, reason: .sessionMistake),
                    randomizeOptions: randomizeOptions
                )
                occurrences.insert(repeatOccurrence, at: insertion)
            }
        }
    }

    mutating func record(_ outcome: AttemptOutcome) {
        record(outcome, previousState: .unseen, newState: outcome == .correct ? .review : .weak)
    }

    mutating func advance() {
        if isViewingHistory { goForward(); return }
        index += 1
        viewingIndex = index
    }

    mutating func goBack() {
        guard canGoBack else { return }
        viewingIndex -= 1
    }

    mutating func goForward() {
        guard canGoForward else { return }
        viewingIndex += 1
    }

    mutating func returnToFrontier() { viewingIndex = index }

    mutating func reconsiderSmartQueue(with candidates: [StudyCard]) {
        guard dynamicallyReconsidersSmartQueue else { return }
        let answeredPrefix = Array(occurrences.prefix(index))
        let remaining = max(0, targetAnswerCount - answeredPrefix.count)
        let appearanceLimit = drillWeak ? 3 : 2
        let refreshed = candidates.filter {
            appearanceCounts[$0.id, default: 0] < appearanceLimit
        }
        let freshOccurrences = refreshed
            .prefix(remaining)
            .map { StudyOccurrence(card: $0, randomizeOptions: randomizeOptions) }
        occurrences = answeredPrefix + freshOccurrences
    }

    mutating func markConceptUnclear(_ id: String) {
        if !summary.unclearConceptIDs.contains(id) { summary.unclearConceptIDs.append(id) }
    }
}

struct MockExamResult: Sendable {
    let correctQuestionIDs: [String]
    let incorrectQuestionIDs: [String]
    let unansweredQuestionIDs: [String]
    var correct: Int { correctQuestionIDs.count }
    var answered: Int { correctQuestionIDs.count + incorrectQuestionIDs.count }
}

struct MockExamBuilder: Sendable {
    static let questionCount = CategoryProfile.examQuestionCount
    static let passingScore = CategoryProfile.passingScore

    func makeExam(from questions: [Question]) -> [Question] {
        Array(questions.shuffled().prefix(Self.questionCount))
    }

    func grade(questions: [Question], answers: [String: String]) -> MockExamResult {
        var correct: [String] = []
        var incorrect: [String] = []
        var unanswered: [String] = []
        for question in questions {
            guard let answer = answers[question.id] else {
                unanswered.append(question.id)
                continue
            }
            if answer == question.correctOptionId {
                correct.append(question.id)
            } else {
                incorrect.append(question.id)
            }
        }
        return MockExamResult(correctQuestionIDs: correct, incorrectQuestionIDs: incorrect, unansweredQuestionIDs: unanswered)
    }

    func passed(correct: Int) -> Bool { correct >= Self.passingScore }
}

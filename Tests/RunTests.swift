import Foundation

extension Bundle { static let module = Bundle.main }

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { if case let .failed(message) = self { return message }; return "failure" }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.failed(message) }
}

func sampleQuestion(_ number: Int, topic: String = "Тема") -> Question {
    let id = "q-\(number)"
    return Question(
        id: id, examNumber: number, stem: "Вопрос \(number) о радиосвязи",
        options: [
            QuestionOption(id: "\(id)-1", text: "Верно"),
            QuestionOption(id: "\(id)-2", text: "Неверно"),
            QuestionOption(id: "\(id)-3", text: "Тоже неверно"),
            QuestionOption(id: "\(id)-4", text: "Ещё один вариант")
        ],
        correctOptionId: "\(id)-1", officialCorrectAnswerText: "Верно", topic: topic, subtopic: topic,
        type: "понять принцип", explanationShort: "Короткое предметное объяснение.",
        explanationBeginner: "Понятное объяснение термина и принципа с нуля.",
        explanationReasoning: "Правильный вариант следует из физического принципа.",
        wrongOptionExplanations: ["\(id)-2": "Противоречит условию.", "\(id)-3": "Описывает другое явление.", "\(id)-4": "Не относится к вопросу."],
        memoryHint: "Свяжите правило с примером.", glossaryTerms: [], figureAsset: nil,
        sourceReference: SourceReference(document: "source.pdf", page: 1, sourceQuestionNumber: number, explanationDocument: "guide.pdf", explanationPage: 1),
        legalHistoricalNote: nil
    )
}

func temporaryURL(_ name: String = "progress.json") -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
}

@main
struct CoreTestRunner {
    @MainActor
    static func main() throws {
        let content = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Content")
        var tests: [(String, () throws -> Void)] = []
        let scheduler = AdaptiveReviewScheduler()

        func answerAndRefresh(
            _ outcome: AttemptOutcome,
            session: inout StudySession,
            bank: [Question],
            progress: inout [String: QuestionProgress],
            completedStudyStep: inout Int
        ) throws -> String {
            guard let card = session.current else { throw TestFailure.failed("Smart Study ended before the expected card") }
            let previous = progress[card.id] ?? QuestionProgress(questionId: card.id)
            completedStudyStep += 1
            let updated = scheduler.applying(
                outcome, to: previous, completedStudyStep: completedStudyStep, selectionReason: card.reason
            )
            progress[card.id] = updated
            session.record(outcome, previousState: previous.state, newState: updated.state)
            session.advance()
            if session.dynamicallyReconsidersSmartQueue, session.smartRefreshLength > 0 {
                let refreshed = scheduler.smartQueue(
                    questions: bank, progress: progress,
                    length: session.smartRefreshLength, completedStudyStep: completedStudyStep
                )
                session.reconsiderSmartQueue(with: refreshed)
            }
            return card.id
        }

        tests.append(("wrong becomes due after five other answers", {
            let failed = scheduler.applying(.incorrect, to: QuestionProgress(questionId: "q"), completedStudyStep: 100)
            try expect(failed.nextDueStudyStep == 106, "wrong due step should be 106")
            try expect(!scheduler.isDue(failed, completedStudyStep: 104), "shown after only four other answers")
            try expect(scheduler.isDue(failed, completedStudyStep: 105), "not due after five other answers")
        }))

        tests.append(("dont know uses five-question gap", {
            let value = scheduler.applying(.dontKnow, to: QuestionProgress(questionId: "q"), completedStudyStep: 7)
            try expect(value.state == .weak && value.dontKnowCount == 1, "don't know not weak")
            try expect(value.nextDueStudyStep == 13, "don't know gap is not five")
        }))

        tests.append(("reveal is a graded failure", {
            let value = scheduler.applying(.revealedBeforeAnswer, to: QuestionProgress(questionId: "q"), completedStudyStep: 12)
            try expect(value.state == .weak && value.revealedCount == 1 && value.correctCount == 0, "reveal counted as knowledge")
            try expect(value.nextDueStudyStep == 18, "reveal gap is not five")
        }))

        tests.append(("review ladder is 5 10 20 40 80", {
            var value = scheduler.applying(.incorrect, to: QuestionProgress(questionId: "q"), completedStudyStep: 1)
            try expect(value.reviewStage == 0 && value.nextDueStudyStep == 7, "failure did not enter stage 5")
            value = scheduler.applying(.correct, to: value, completedStudyStep: 7)
            try expect(value.reviewStage == 1 && value.nextDueStudyStep == 18, "recovery did not schedule 10")
            value = scheduler.applying(.correct, to: value, completedStudyStep: 18)
            try expect(value.reviewStage == 2 && value.nextDueStudyStep == 39, "second recall did not schedule 20")
            value = scheduler.applying(.correct, to: value, completedStudyStep: 39)
            try expect(value.reviewStage == 3 && value.nextDueStudyStep == 80, "third recall did not schedule 40")
            value = scheduler.applying(.correct, to: value, completedStudyStep: 80)
            try expect(value.reviewStage == 4 && value.nextDueStudyStep == 161 && value.state == .mastered, "fourth recall did not schedule 80/master")
        }))

        tests.append(("first correct answer starts at distance five", {
            let value = scheduler.applying(.correct, to: QuestionProgress(questionId: "q"), completedStudyStep: 20)
            try expect(value.reviewStage == 0 && value.nextDueStudyStep == 26, "new correct card skipped the five-question stage")
        }))

        tests.append(("lapse removes mastery and rebuilds confidence", {
            var old = QuestionProgress(questionId: "q")
            old.state = .mastered; old.reviewStage = 4; old.successfulSpacedReviews = 6
            let value = scheduler.applying(.incorrect, to: old, completedStudyStep: 90)
            try expect(value.state == .weak && value.reviewStage == 0 && value.lapseCount == 1, "mastered lapse was not reset")
            try expect(value.nextDueStudyStep == 96, "lapse did not use short interval")
        }))

        tests.append(("study step persists across restart", {
            let url = temporaryURL()
            let question = sampleQuestion(1)
            let first = AppStore(persistenceURL: url, loadContent: false)
            _ = first.record(.incorrect, for: question)
            _ = first.record(.correct, for: sampleQuestion(2))
            let restarted = AppStore(persistenceURL: url, loadContent: false)
            try expect(restarted.studyStep == 2, "studyStep reset on restart")
            try expect(restarted.progressFor(question).nextDueStudyStep == 7, "due distance changed on restart")
        }))

        tests.append(("legacy settings default to large reading size", {
            let legacy = Data(#"{"defaultSessionLength":30,"randomizeOptions":false,"explanationStyle":"Кратко"}"#.utf8)
            let settings = try AppStore.decoder.decode(UserSettings.self, from: legacy)
            try expect(settings.defaultSessionLength == 30 && settings.readingSize == .large, "legacy settings migration changed values or text default")
        }))

        tests.append(("session boundary preserves remaining distance", {
            let url = temporaryURL()
            let failed = sampleQuestion(1)
            let first = AppStore(persistenceURL: url, loadContent: false)
            _ = first.record(.incorrect, for: failed)
            _ = first.record(.correct, for: sampleQuestion(2))
            _ = first.record(.correct, for: sampleQuestion(3))
            let restarted = AppStore(persistenceURL: url, loadContent: false)
            let remaining = scheduler.remainingQuestionDistance(restarted.progressFor(failed), completedStudyStep: restarted.studyStep)
            try expect(remaining == 3, "remaining question distance did not survive restart")
        }))

        tests.append(("question is never selected before due", {
            let q = sampleQuestion(1)
            var state = QuestionProgress(questionId: q.id)
            state.state = .weak; state.nextDueStudyStep = 20
            let early = scheduler.smartQueue(questions: [q], progress: [q.id: state], length: 20, completedStudyStep: 10)
            try expect(early.isEmpty, "non-due question entered Smart Study")
        }))

        tests.append(("non-due mastered bank yields empty Smart Study", {
            let bank = (1...CategoryProfile.bankCount).map { sampleQuestion($0) }
            let state = Dictionary(uniqueKeysWithValues: bank.map { q -> (String, QuestionProgress) in
                var progress = QuestionProgress(questionId: q.id)
                progress.state = .mastered; progress.reviewStage = 4; progress.nextDueStudyStep = 500
                return (q.id, progress)
            })
            let queue = scheduler.smartQueue(questions: bank, progress: state, length: 20, completedStudyStep: 100)
            try expect(queue.isEmpty, "Smart Study fabricated mandatory mastered reviews")
        }))

        tests.append(("session repeat respects minimum gap and appearance cap", {
            let bank = (1...20).map { sampleQuestion($0) }
            var session = StudySession(questions: bank)
            session.record(.incorrect)
            let repeatIndex = session.queue.lastIndex(where: { $0.id == bank[0].id })
            try expect(repeatIndex == 6, "failure was not placed after five other cards")
            repeat { session.advance() } while session.currentQuestion?.id != bank[0].id
            session.record(.incorrect)
            try expect(session.queue.filter({ $0.id == bank[0].id }).count == 2, "normal session exceeded repeat cap")
        }))

        tests.append(("short session does not violate scheduled gap", {
            var session = StudySession(questions: (1...4).map { sampleQuestion($0) })
            session.record(.incorrect)
            try expect(session.queue.count == 4, "repeat inserted without five intervening cards")
        }))

        tests.append(("history A preserves answered occurrence presentation", {
            let q1 = sampleQuestion(1), q2 = sampleQuestion(2)
            var session = StudySession(questions: [q1, q2], randomizeOptions: true)
            let order = session.currentOccurrence!.displayedOptions.map(\.id)
            session.record(.incorrect, selectedOptionId: q1.options[1].id, previousState: .unseen, newState: .learning)
            session.advance()
            session.goBack()
            let historical = session.currentOccurrence!
            try expect(historical.displayedOptions.map(\.id) == order, "historical option order changed")
            try expect(historical.selectedOptionId == q1.options[1].id && historical.outcome == .incorrect, "historical answer state changed")
        }))

        tests.append(("history B navigation does not record progress", {
            let url = temporaryURL()
            let q1 = sampleQuestion(1), q2 = sampleQuestion(2)
            let store = AppStore(persistenceURL: url, loadContent: false)
            var session = StudySession(questions: [q1, q2], randomizeOptions: false)
            let before = store.progressFor(q1)
            let updated = store.record(.correct, for: q1)
            session.record(.correct, selectedOptionId: q1.correctOptionId, previousState: before.state, newState: updated.state)
            session.advance()
            let step = store.studyStep, progress = store.progress, attempts = session.summary.attempts
            session.goBack(); session.goForward()
            try expect(store.studyStep == step && store.progress == progress, "history navigation mutated scheduler progress")
            try expect(session.summary.attempts == attempts, "history navigation appended a summary attempt")
        }))

        tests.append(("history C active frontier keeps option order", {
            var session = StudySession(questions: [sampleQuestion(1), sampleQuestion(2)], randomizeOptions: true)
            session.record(.correct); session.advance()
            let frontierID = session.currentOccurrence!.id
            let order = session.currentOccurrence!.displayedOptions.map(\.id)
            session.goBack(); session.goForward()
            try expect(session.currentOccurrence!.id == frontierID && session.currentOccurrence!.displayedOptions.map(\.id) == order, "frontier presentation changed")
        }))

        tests.append(("history D navigates several occurrences both ways", {
            var session = StudySession(questions: (1...4).map { sampleQuestion($0) }, randomizeOptions: false)
            for _ in 0..<3 { session.record(.correct); session.advance() }
            session.goBack(); session.goBack(); session.goBack()
            try expect(session.currentQuestion?.id == "q-1", "multi-step back failed")
            session.goForward(); session.goForward(); session.goForward()
            try expect(session.currentQuestion?.id == "q-4" && !session.isViewingHistory, "multi-step forward failed")
        }))

        tests.append(("history E duplicate question occurrences are independent", {
            let q = sampleQuestion(1)
            var session = StudySession(questions: [q, q], randomizeOptions: false)
            let firstID = session.currentOccurrence!.id
            session.record(.incorrect, selectedOptionId: q.options[1].id, previousState: .unseen, newState: .learning)
            session.advance()
            let secondID = session.currentOccurrence!.id
            try expect(firstID != secondID && session.currentOccurrence!.outcome == nil, "duplicate occurrence reused presentation state")
            session.record(.correct, selectedOptionId: q.correctOptionId, previousState: .learning, newState: .review)
            session.advance(); session.goBack(); session.goBack()
            try expect(session.currentOccurrence!.outcome == .incorrect, "first duplicate occurrence was overwritten")
        }))

        tests.append(("history F dynamic refresh preserves answered occurrences", {
            let questions = (1...4).map { sampleQuestion($0) }
            var session = StudySession(cards: questions.prefix(3).map { StudyCard(question: $0, reason: .new) }, dynamicallyReconsidersSmartQueue: true, randomizeOptions: false)
            session.record(.correct); session.advance()
            let answered = session.occurrences[0]
            let oldFutureIDs = Array(session.occurrences.dropFirst()).map(\.id)
            session.reconsiderSmartQueue(with: [StudyCard(question: questions[3], reason: .new)])
            try expect(session.occurrences[0] == answered, "dynamic refresh changed answered history")
            try expect(Array(session.occurrences.dropFirst()).map(\.id) != oldFutureIDs, "dynamic refresh did not replace future occurrences")
        }))

        tests.append(("history G historical answer cannot be submitted twice", {
            var session = StudySession(questions: [sampleQuestion(1), sampleQuestion(2)], randomizeOptions: false)
            session.record(.incorrect); session.advance(); session.goBack()
            let summary = session.summary
            session.record(.correct)
            try expect(session.summary.total == summary.total && session.summary.attempts == summary.attempts, "historical occurrence accepted a second answer")
        }))

        tests.append(("history H bookmark and note persist while looking backward", {
            let url = temporaryURL()
            let q1 = sampleQuestion(1), q2 = sampleQuestion(2)
            let store = AppStore(persistenceURL: url, loadContent: false)
            var session = StudySession(questions: [q1, q2], randomizeOptions: false)
            session.record(.correct); session.advance(); session.goBack()
            store.toggleBookmark(q1); store.updateNote("Историческая заметка", for: q1)
            let restored = AppStore(persistenceURL: url, loadContent: false)
            try expect(restored.progressFor(q1).bookmarked && restored.progressFor(q1).note == "Историческая заметка", "editable historical metadata did not persist")
        }))

        tests.append(("historical errors filter includes recovered question", {
            var recovered = QuestionProgress(questionId: "q")
            recovered.state = .mastered; recovered.incorrectCount = 1
            try expect(WeakQuestionFilter.historicalErrors.matches(recovered), "recovered historical error was omitted")
            try expect(!WeakQuestionFilter.all.matches(recovered), "recovered question incorrectly remained currently weak")
        }))

        tests.append(("five-round drill has exactly five complete rounds", {
            let questions = (1...4).map { sampleQuestion($0) }
            var calls = 0
            let session = StudySession(intensiveQuestions: questions, rounds: 5, randomizeOptions: false) { values in
                calls += 1
                return calls.isMultiple(of: 2) ? Array(values.reversed()) : values
            }
            try expect(session.occurrences.count == 20 && calls == 5, "round count or independent shuffle calls wrong")
            for round in 1...5 {
                let ids = session.occurrences.filter { $0.round == round }.map { $0.card.question.id }
                try expect(ids.count == 4 && Set(ids) == Set(questions.map(\.id)), "round \(round) is not a full snapshot")
            }
            let orders = (1...5).map { round in session.occurrences.filter { $0.round == round }.map { $0.card.question.id } }
            try expect(orders[0] != orders[1], "rounds were not independently shuffled")
        }))

        tests.append(("round boundary avoids immediate duplicate", {
            let questions = (1...3).map { sampleQuestion($0) }
            var calls = 0
            let session = StudySession(intensiveQuestions: questions, rounds: 3, randomizeOptions: false) { values in
                calls += 1
                return calls.isMultiple(of: 2) ? Array(values.reversed()) : values
            }
            for boundary in [3, 6] {
                try expect(session.occurrences[boundary - 1].card.question.id != session.occurrences[boundary].card.question.id, "round boundary duplicated a question")
            }
        }))

        tests.append(("starting round drill leaves stored progress unchanged", {
            let url = temporaryURL(), q = sampleQuestion(1)
            let store = AppStore(persistenceURL: url, loadContent: false)
            _ = store.record(.incorrect, for: q)
            let before = store.progress
            _ = StudySession(intensiveQuestions: [q], rounds: 5, randomizeOptions: false)
            try expect(store.progress == before, "starting intensive drill reset progress")
        }))

        tests.append(("round drill scheduler distinguishes early and due correct", {
            var progress = QuestionProgress(questionId: "q")
            progress.state = .review; progress.reviewStage = 1; progress.successfulSpacedReviews = 1; progress.nextDueStudyStep = 20
            let early = scheduler.applying(.correct, to: progress, completedStudyStep: 10, selectionReason: .manuallySelected)
            try expect(early.reviewStage == 1 && early.successfulSpacedReviews == 1, "early round advanced spaced stage")
            let due = scheduler.applying(.correct, to: early, completedStudyStep: early.nextDueStudyStep!, selectionReason: .manuallySelected)
            try expect(due.reviewStage == 2 && due.successfulSpacedReviews == 2, "later due round did not advance spaced stage")
        }))

        tests.append(("due weak questions outrank new questions", {
            let weak = sampleQuestion(1)
            let fresh = sampleQuestion(2)
            var weakProgress = QuestionProgress(questionId: weak.id)
            weakProgress.state = .weak; weakProgress.nextDueStudyStep = 10
            let queue = scheduler.smartQueue(questions: [fresh, weak], progress: [weak.id: weakProgress], length: 2, completedStudyStep: 9)
            try expect(queue.map(\.id) == [weak.id, fresh.id], "new question outranked due weak question")
            try expect(queue.map(\.reason) == [.weak, .new], "selection reasons are not explicit")
        }))

        tests.append(("case A due card returns inside the same long Smart Study session", {
            let bank = (1...30).map { sampleQuestion($0) }
            var progress: [String: QuestionProgress] = [:]
            var step = 0
            let initial = scheduler.smartQueue(questions: bank, progress: progress, length: 20, completedStudyStep: step)
            var session = StudySession(cards: initial, dynamicallyReconsidersSmartQueue: true)
            var sequence: [String] = []
            for _ in 0..<7 {
                sequence.append(try answerAndRefresh(.correct, session: &session, bank: bank, progress: &progress, completedStudyStep: &step))
            }
            try expect(sequence == ["q-1", "q-2", "q-3", "q-4", "q-5", "q-6", "q-1"], "due Q1 did not return after five other cards: \(sequence)")
        }))

        tests.append(("case B and G normal due reviews outrank a large unseen bank", {
            let due = sampleQuestion(1)
            let unseen = (2...CategoryProfile.bankCount).map { sampleQuestion($0) }
            var dueProgress = QuestionProgress(questionId: due.id)
            dueProgress.state = .review
            dueProgress.reviewStage = 2
            dueProgress.nextDueStudyStep = 101
            let queue = scheduler.smartQueue(
                questions: unseen + [due], progress: [due.id: dueProgress], length: 20, completedStudyStep: 100
            )
            try expect(queue.first?.id == due.id && queue.first?.reason == .due, "unseen cards starved a normal due review")
        }))

        tests.append(("case C early correct is practice only", {
            var value = QuestionProgress(questionId: "q")
            value.state = .review
            value.reviewStage = 2
            value.successfulSpacedReviews = 2
            value.nextDueStudyStep = 100
            let early = scheduler.applying(.correct, to: value, completedStudyStep: 82, selectionReason: .manuallySelected)
            try expect(early.correctCount == 1 && early.attempts == 1, "early practice was not recorded")
            try expect(early.reviewStage == 2 && early.successfulSpacedReviews == 2, "early practice advanced spaced-review progress")
            try expect(early.nextDueStudyStep == 101, "same-question practice incorrectly counted as an OTHER answer")
        }))

        tests.append(("case D genuine due correct advances the stage", {
            var value = QuestionProgress(questionId: "q")
            value.state = .review
            value.reviewStage = 2
            value.successfulSpacedReviews = 2
            value.nextDueStudyStep = 100
            let due = scheduler.applying(.correct, to: value, completedStudyStep: 100, selectionReason: .due)
            try expect(due.reviewStage == 3 && due.successfulSpacedReviews == 3, "due correct did not advance spaced-review progress")
            try expect(due.nextDueStudyStep == 141, "stage 3 did not schedule forty other questions")
        }))

        tests.append(("case E and F failed card waits for five others then returns", {
            let bank = (1...30).map { sampleQuestion($0) }
            var progress: [String: QuestionProgress] = [:]
            var step = 0
            let initial = scheduler.smartQueue(questions: bank, progress: progress, length: 20, completedStudyStep: step)
            var session = StudySession(cards: initial, dynamicallyReconsidersSmartQueue: true)
            var sequence = [try answerAndRefresh(.incorrect, session: &session, bank: bank, progress: &progress, completedStudyStep: &step)]
            for _ in 0..<6 {
                sequence.append(try answerAndRefresh(.correct, session: &session, bank: bank, progress: &progress, completedStudyStep: &step))
            }
            try expect(Array(sequence.prefix(6)) == ["q-1", "q-2", "q-3", "q-4", "q-5", "q-6"], "failed card repeated before five other answers: \(sequence)")
            try expect(sequence[6] == "q-1", "failed card did not return after five other answers: \(sequence)")
        }))

        tests.append(("case H rapid manual correct answers cannot create Mastered", {
            var value = scheduler.applying(.correct, to: QuestionProgress(questionId: "q"), completedStudyStep: 1, selectionReason: .manuallySelected)
            for step in 2...100 {
                value = scheduler.applying(.correct, to: value, completedStudyStep: step, selectionReason: .manuallySelected)
            }
            try expect(value.correctCount == 100, "manual practice attempts were lost")
            try expect(value.reviewStage == 0 && value.successfulSpacedReviews == 0, "rapid practice advanced spaced-review progress")
            try expect(value.state != .mastered, "rapid manual practice created Mastered")
            try expect(value.nextDueStudyStep == 106, "same-question answers were counted as other questions")
        }))

        tests.append(("500-answer Smart Study simulation prevents due starvation", {
            let bank = (1...120).map { sampleQuestion($0, topic: "Тема \(($0 - 1) % 6)") }
            var progress: [String: QuestionProgress] = [:]
            var completed = 0
            var failureStep: [String: Int] = [:]
            var dueSelections = 0
            var newSelections = 0
            var maximumOverdue = 0

            for answerNumber in 1...500 {
                let dueNow = bank.filter {
                    let value = progress[$0.id] ?? QuestionProgress(questionId: $0.id)
                    return value.state != .mastered && scheduler.isDue(value, completedStudyStep: completed)
                }
                let queue = scheduler.smartQueue(questions: bank, progress: progress, length: 20, completedStudyStep: completed)
                guard let card = queue.first else { throw TestFailure.failed("simulation ran out of eligible cards at answer \(answerNumber)") }
                if !dueNow.isEmpty {
                    try expect(dueNow.contains(where: { $0.id == card.id }), "an unseen card was selected while a non-mastered review was due")
                    dueSelections += 1
                } else if card.reason == .new {
                    newSelections += 1
                }
                if let failedAt = failureStep[card.id] {
                    try expect(completed - failedAt >= 5, "failed card returned before five other answers")
                    failureStep[card.id] = nil
                }
                let previous = progress[card.id] ?? QuestionProgress(questionId: card.id)
                if let due = previous.nextDueStudyStep {
                    maximumOverdue = max(maximumOverdue, max(0, completed + 1 - due))
                }
                completed += 1
                let outcome: AttemptOutcome = answerNumber.isMultiple(of: 37) ? .incorrect : .correct
                progress[card.id] = scheduler.applying(outcome, to: previous, completedStudyStep: completed, selectionReason: card.reason)
                if outcome.isFailure { failureStep[card.id] = completed }
            }
            print("SIMULATION 500 answers; due selections=\(dueSelections); new selections=\(newSelections); max overdue=\(maximumOverdue)")
            try expect(dueSelections > 300 && newSelections > 0, "simulation did not exercise both due and new selection paths")
            try expect(maximumOverdue < 120, "a due review was effectively starved")
        }))

        tests.append(("requested length does not override eligibility", {
            let due = sampleQuestion(1)
            var dueProgress = QuestionProgress(questionId: due.id)
            dueProgress.state = .review; dueProgress.nextDueStudyStep = 2
            let mastered = (2...30).map { sampleQuestion($0) }
            var state = [due.id: dueProgress]
            for q in mastered {
                var value = QuestionProgress(questionId: q.id)
                value.state = .mastered; value.nextDueStudyStep = 999
                state[q.id] = value
            }
            let queue = scheduler.smartQueue(questions: [due] + mastered, progress: state, length: 20, completedStudyStep: 1)
            try expect(queue.count == 1 && queue[0].id == due.id, "session length fabricated non-due cards")
        }))

        tests.append(("due maintenance remains a small slice", {
            let bank = (1...100).map { sampleQuestion($0) }
            let state = Dictionary(uniqueKeysWithValues: bank.map { q -> (String, QuestionProgress) in
                var value = QuestionProgress(questionId: q.id)
                value.state = .mastered; value.nextDueStudyStep = 1
                return (q.id, value)
            })
            let queue = scheduler.smartQueue(questions: bank, progress: state, length: 20, completedStudyStep: 1)
            try expect(queue.count == 2 && queue.allSatisfy { $0.reason == .maintenance }, "maintenance cap is not 10 percent")
        }))

        tests.append(("option shuffling preserves correctness ID", {
            let q = sampleQuestion(1)
            for _ in 0..<30 {
                let shuffled = q.options.shuffled()
                try expect(shuffled.contains(where: { $0.id == q.correctOptionId }), "correct ID lost while shuffling")
                try expect(shuffled.first(where: { $0.id == q.correctOptionId })?.text == "Верно", "correct option mapping changed")
            }
        }))

        tests.append(("mock exam is 25 unique questions with 20 threshold", {
            let bank = (1...CategoryProfile.bankCount).map { sampleQuestion($0) }
            let builder = MockExamBuilder()
            let exam = builder.makeExam(from: bank)
            try expect(exam.count == 25 && Set(exam.map(\.id)).count == 25, "mock selection invalid")
            try expect(!builder.passed(correct: 19) && builder.passed(correct: 20), "pass threshold invalid")
        }))

        tests.append(("early mock finish distinguishes unanswered", {
            let exam = (1...25).map { sampleQuestion($0) }
            let answers = Dictionary(uniqueKeysWithValues: exam.prefix(5).map { ($0.id, $0.correctOptionId) })
            let result = MockExamBuilder().grade(questions: exam, answers: answers)
            try expect(result.correct == 5 && result.answered == 5 && result.unansweredQuestionIDs.count == 20, "unanswered exam state is wrong")
            try expect(result.incorrectQuestionIDs.isEmpty, "unanswered questions became incorrect")
        }))

        tests.append(("mock adaptive history records only submitted answers", {
            let url = temporaryURL()
            let exam = (1...25).map { sampleQuestion($0) }
            let answers = [exam[0].id: exam[0].correctOptionId, exam[1].id: exam[1].options[1].id]
            let store = AppStore(persistenceURL: url, loadContent: false)
            let result = store.finishMockExam(questions: exam, answers: answers)
            try expect(store.studyStep == 2 && result.unansweredQuestionIDs.count == 23, "mock studyStep counted unanswered")
            try expect(store.progressFor(exam[0]).correctCount == 1, "submitted correct answer missing")
            try expect(store.progressFor(exam[1]).incorrectCount == 1, "submitted wrong answer missing")
            try expect(store.progressFor(exam[2]).attempts == 0, "unanswered question contaminated progress")
        }))

        tests.append(("notes bookmarks and scheduler state persist", {
            let url = temporaryURL()
            let q = sampleQuestion(9)
            let first = AppStore(persistenceURL: url, loadContent: false)
            _ = first.record(.dontKnow, for: q)
            first.toggleBookmark(q)
            first.updateNote("Проверить формулу", for: q)
            let restarted = AppStore(persistenceURL: url, loadContent: false)
            let value = restarted.progressFor(q)
            try expect(value.dontKnowCount == 1 && value.bookmarked && value.note == "Проверить формулу", "question-owned data did not persist")
            try expect(value.nextDueStudyStep == 7, "scheduler state did not persist")
        }))

        tests.append(("concept weakness is visible and learnable", {
            let url = temporaryURL()
            let store = AppStore(persistenceURL: url, loadContent: false)
            store.markConceptWeak("swr"); store.markConceptWeak("swr")
            try expect(store.weakConceptIds.contains("swr") && store.conceptProgressFor("swr").unclearCount == 2, "weak concept was hidden")
            store.markConceptUnderstood("swr")
            try expect(!store.weakConceptIds.contains("swr") && store.conceptProgressFor("swr").isLearned, "understood concept remained weak")
        }))

        tests.append(("personal glossary CRUD persists", {
            let url = temporaryURL()
            let first = AppStore(persistenceURL: url, loadContent: false)
            var entry = first.addPersonalGlossaryEntry(term: "Балун", relatedQuestionIDs: ["q-1"])
            entry.shortDefinition = "Симметрирующее устройство"
            entry.personalNotes = "Проверить тип 1:1"
            first.updatePersonalGlossaryEntry(entry)
            let restarted = AppStore(persistenceURL: url, loadContent: false)
            try expect(restarted.personalGlossary.first?.shortDefinition == "Симметрирующее устройство", "personal term did not persist")
            restarted.deletePersonalGlossaryEntry(id: entry.id)
            try expect(restarted.personalGlossary.isEmpty, "personal term was not deleted")
        }))

        tests.append(("personal glossary rejects empty terms and invalid question IDs", {
            let url = temporaryURL()
            let store = AppStore(persistenceURL: url)
            _ = store.addPersonalGlossaryEntry(term: "   ", relatedQuestionIDs: ["q-001"])
            try expect(store.personalGlossary.isEmpty, "empty personal term was saved")
            let entry = store.addPersonalGlossaryEntry(term: "  Балун  ", relatedQuestionIDs: ["q-001", "q-001"])
            try expect(entry.term == "Балун" && entry.relatedQuestionIDs == ["q-001"], "personal glossary normalization failed")
            let validated = AppStore.validatedQuestionIDs(["q-001", "missing", "q-001"], validQuestionIDs: ["q-001"])
            try expect(validated == ["q-001"], "invalid related question ID survived validation")
        }))

        tests.append(("backup round trip restores all user state", {
            let sourceURL = temporaryURL()
            let exportURL = temporaryURL("backup.json")
            let targetURL = temporaryURL()
            let q = sampleQuestion(3)
            let source = AppStore(persistenceURL: sourceURL, loadContent: false)
            _ = source.record(.incorrect, for: q)
            source.updateNote("заметка", for: q)
            source.markConceptWeak("dipole")
            _ = source.addPersonalGlossaryEntry(term: "Фидер", relatedQuestionIDs: [q.id])
            source.settings.defaultSessionLength = 30
            source.saveProgress()
            try source.exportBackup(to: exportURL)
            let target = AppStore(persistenceURL: targetURL, loadContent: false)
            try target.importBackup(from: exportURL)
            try expect(target.studyStep == 1 && target.progressFor(q).incorrectCount == 1, "progress/step backup failed")
            try expect(target.progressFor(q).note == "заметка" && target.weakConceptIds.contains("dipole"), "notes/concepts backup failed")
            try expect(target.personalGlossary.count == 1 && target.settings.defaultSessionLength == 30, "glossary/settings backup failed")
        }))

        tests.append(("category-2 backup identity is rejected", {
            let source = AppStore(persistenceURL: temporaryURL(), loadContent: false)
            _ = source.record(.correct, for: sampleQuestion(1))
            let validURL = temporaryURL("valid-backup.json")
            let foreignURL = temporaryURL("category-2-backup.json")
            try source.exportBackup(to: validURL)
            var foreign = try AppStore.decoder.decode(ProgressBackup.self, from: Data(contentsOf: validURL))
            foreign.productIdentity = "HAMTrainer"
            try AppStore.encoder.encode(foreign).write(to: foreignURL)
            let target = AppStore(persistenceURL: temporaryURL(), loadContent: false)
            do {
                try target.importBackup(from: foreignURL)
                throw TestFailure.failed("category-2 backup unexpectedly succeeded")
            } catch is TestFailure {
                throw TestFailure.failed("category-2 backup unexpectedly succeeded")
            } catch {}
            try expect(target.studyStep == 0 && target.progress.isEmpty, "foreign backup changed category-3 progress")
        }))

        tests.append(("malformed import does not erase current data", {
            let url = temporaryURL()
            let malformed = temporaryURL("broken.json")
            let q = sampleQuestion(4)
            let store = AppStore(persistenceURL: url, loadContent: false)
            _ = store.record(.correct, for: q)
            try Data("{not-json".utf8).write(to: malformed)
            do {
                try store.importBackup(from: malformed)
                throw TestFailure.failed("malformed import unexpectedly succeeded")
            } catch is TestFailure {
                throw TestFailure.failed("malformed import unexpectedly succeeded")
            } catch {}
            try expect(store.progressFor(q).correctCount == 1 && store.studyStep == 1, "malformed import mutated current state")
        }))

        tests.append(("session summary tracks outcomes and transitions", {
            let q = sampleQuestion(1)
            var session = StudySession(questions: [q])
            session.record(.dontKnow, previousState: .unseen, newState: .weak)
            try expect(session.summary.total == 1 && session.summary.dontKnow == 1, "summary outcome counts wrong")
            try expect(session.summary.becameWeak == 1 && session.summary.mistakeQuestionIDs == [q.id], "summary transition/mistake list wrong")
        }))

        tests.append(("content bank integrity and provenance", {
            let data = try Data(contentsOf: content.appendingPathComponent("questions.json"))
            let questions = try AppStore.decoder.decode([Question].self, from: data)
            let expected = CategoryProfile.examNumbers
            try expect(questions.count == CategoryProfile.bankCount && Set(questions.map(\.examNumber)) == expected, "wrong question selection")
            try expect(Set(questions.map(\.id)).count == CategoryProfile.bankCount, "duplicate IDs")
            for question in questions {
                try expect(!question.stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "empty stem \(question.examNumber)")
                try expect(question.options.count == 4 && question.options.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "incomplete options \(question.examNumber)")
                try expect(question.options.contains(where: { $0.id == question.correctOptionId }), "invalid answer \(question.examNumber)")
                try expect(question.sourceReference.sourceQuestionNumber == question.examNumber, "missing provenance \(question.examNumber)")
                if let asset = question.figureAsset {
                    try expect(FileManager.default.fileExists(atPath: content.appendingPathComponent(asset).path), "missing \(asset)")
                }
            }
        }))

        tests.append(("feeder memory hints match questions 181 and 182", {
            let questions = try AppStore.decoder.decode([Question].self, from: Data(contentsOf: content.appendingPathComponent("questions.json")))
            let q181 = questions.first(where: { $0.examNumber == 181 })
            let q182 = questions.first(where: { $0.examNumber == 182 })
            try expect(q181?.memoryHint == "Фидер должен быть электрической линией: коаксиальным кабелем или двухпроводной линией.", "question 181 retained unrelated dipole hint")
            try expect(q182?.memoryHint == "Экранированный коаксиальный кабель можно вести у конструкций и, с подходящей оболочкой, под землёй.", "question 182 retained unrelated vertical hint")
        }))

        tests.append(("all glossary references resolve", {
            let questions = try AppStore.decoder.decode([Question].self, from: Data(contentsOf: content.appendingPathComponent("questions.json")))
            let glossary = try AppStore.decoder.decode([GlossaryEntry].self, from: Data(contentsOf: content.appendingPathComponent("glossary.json")))
            let ids = Set(glossary.map(\.id))
            let missing = Set(questions.flatMap(\.glossaryTerms)).subtracting(ids)
            try expect(missing.isEmpty, "unresolved glossary IDs: \(missing.sorted())")
            try expect(glossary.count == 127, "category-3 glossary count is not exact: \(glossary.count)")
        }))

        tests.append(("topic quick reference covers the exact bank without recording", {
            let questions = try AppStore.decoder.decode([Question].self, from: Data(contentsOf: content.appendingPathComponent("questions.json")))
            let topics = Dictionary(grouping: questions, by: \.topic)
            try expect(!topics.isEmpty && topics.values.allSatisfy { !$0.isEmpty }, "empty topic is visible")
            try expect(topics.values.reduce(0) { $0 + $1.count } == CategoryProfile.bankCount, "topic counts do not sum to 218")
            try expect(questions.allSatisfy { !$0.officialCorrectAnswerText.isEmpty }, "quick-reference answer missing")
            let sample = questions.first!
            try expect(sample.matchesReferenceQuery("\(sample.examNumber)"), "topic search cannot find question number")
            try expect(sample.matchesReferenceQuery(sample.officialCorrectAnswerText), "topic search cannot find correct answer")
            try expect(sample.matchesReferenceQuery(String(sample.stem.prefix(20))), "topic search cannot find stem")
            let store = AppStore(persistenceURL: temporaryURL(), loadContent: false)
            _ = sample.matchesReferenceQuery(sample.explanationShort)
            try expect(store.studyStep == 0 && store.progress.isEmpty, "reference browsing recorded an attempt")
        }))

        tests.append(("required category-3 figures use the four audited shared assets", {
            let questions = try AppStore.decoder.decode([Question].self, from: Data(contentsOf: content.appendingPathComponent("questions.json")))
            let byNumber = Dictionary(uniqueKeysWithValues: questions.map { ($0.examNumber, $0) })
            let expected: [Int: String] = [
                22: "diagrams/questions/cept-visit-prefixes.png", 23: "diagrams/questions/cept-visit-prefixes.png",
                32: "diagrams/questions/harec-national-licenses.png",
                173: "diagrams/questions/fm-transmitter.png", 174: "diagrams/questions/fm-transmitter.png",
                175: "diagrams/questions/fm-transmitter.png", 176: "diagrams/questions/fm-transmitter.png",
                177: "diagrams/questions/superhet-receiver.png", 178: "diagrams/questions/superhet-receiver.png",
                179: "diagrams/questions/superhet-receiver.png", 180: "diagrams/questions/superhet-receiver.png",
            ]
            for (number, asset) in expected {
                try expect(byNumber[number]?.figureAsset == asset, "wrong figure mapping for Q\(number)")
                try expect(FileManager.default.fileExists(atPath: content.appendingPathComponent(asset).path), "missing figure for Q\(number)")
            }
        }))

        tests.append(("runtime explanations are structurally complete", {
            let questions = try AppStore.decoder.decode([Question].self, from: Data(contentsOf: content.appendingPathComponent("questions.json")))
            var wrongExplanationCount = 0
            for question in questions {
                try expect(!question.explanationShort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "missing short explanation: \(question.examNumber)")
                try expect(!question.explanationBeginner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "missing beginner explanation: \(question.examNumber)")
                try expect(!question.explanationReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "missing reasoning: \(question.examNumber)")
                try expect(question.wrongOptionExplanations.count == 3, "wrong-option coverage: \(question.examNumber)")
                try expect(question.wrongOptionExplanations.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "empty wrong-option explanation: \(question.examNumber)")
                try expect(question.wrongOptionExplanations[question.correctOptionId] == nil, "correct option present in wrong map: \(question.examNumber)")
                wrongExplanationCount += question.wrongOptionExplanations.count
            }
            try expect(wrongExplanationCount == 654, "wrong-option authored coverage is \(wrongExplanationCount), expected 654")
        }))

        tests.append(("clean extracted wrong options map to stable IDs", {
            let questions = try AppStore.decoder.decode([Question].self, from: Data(contentsOf: content.appendingPathComponent("questions.json")))
            let byNumber = Dictionary(uniqueKeysWithValues: questions.map { ($0.examNumber, $0) })
            let expected = [23: "q-023-option-4", 32: "q-032-option-4", 419: "q-419-option-4"]
            for (number, optionID) in expected {
                try expect(byNumber[number]?.wrongOptionExplanations[optionID]?.isEmpty == false, "clean mapping missing for question \(number)")
            }
        }))

        var failures = 0
        for (name, test) in tests {
            do { try test(); print("PASS  \(name)") }
            catch { failures += 1; print("FAIL  \(name): \(error)") }
        }
        print("\n\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 { throw TestFailure.failed("\(failures) test(s) failed") }
    }
}

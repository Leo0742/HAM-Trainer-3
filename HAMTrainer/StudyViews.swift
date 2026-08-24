import SwiftUI

struct SmartStudyView: View {
    @EnvironmentObject private var store: AppStore
    @State private var length = 20
    @State private var session: StudySession?
    @State private var noRequiredReviews = false

    var body: some View {
        Group {
            if let session {
                StudyRunnerView(session: session, onFinish: { self.session = nil })
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 46)).foregroundStyle(.tint)
                    Text("Умная учёба").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Сессия сначала берёт созревшие слабые и обычные повторы, затем новые вопросы. Интервалы измеряются количеством отвеченных карточек, а не днями.")
                        .font(.title3).foregroundStyle(.secondary).frame(maxWidth: 700, alignment: .leading)
                    Picker("Длина", selection: $length) {
                        ForEach([10, 20, 30, 40], id: \.self) { Text("\($0) вопросов").tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 520)
                    Button("Начать сессию") {
                        let cards = store.smartCards(length: length)
                        if cards.isEmpty { noRequiredReviews = true }
                        else { session = StudySession(cards: cards, dynamicallyReconsidersSmartQueue: true, randomizeOptions: store.settings.randomizeOptions) }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    if noRequiredReviews {
                        ContentUnavailableView(
                            "Обязательных повторений сейчас нет",
                            systemImage: "checkmark.seal",
                            description: Text("Умная учёба не подставляет неготовые освоенные вопросы. Можно открыть слабые вопросы, случайную тему или пробный экзамен.")
                        ).frame(maxWidth: 700)
                    }
                    HStack(spacing: 22) {
                        Label("Ошибки возвращаются после 5 других вопросов", systemImage: "arrow.uturn.forward")
                        Label("Не больше двух появлений", systemImage: "shield.lefthalf.filled")
                    }.font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }.padding(38).frame(maxWidth: .infinity, alignment: .leading)
                    .onAppear { length = store.settings.defaultSessionLength }
            }
        }.navigationTitle("Умная учёба")
    }
}

struct StudyRunnerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var session: StudySession
    let onFinish: () -> Void

    init(session: StudySession, onFinish: @escaping () -> Void) {
        _session = State(initialValue: session)
        self.onFinish = onFinish
    }

    var body: some View {
        if session.isComplete {
            SessionSummaryView(
                summary: session.summary,
                onReviewMistakes: reviewMistakes,
                onReviewWeak: reviewWeak,
                onContinueSmart: continueSmart,
                onClose: onFinish
            )
        } else if let occurrence = session.currentOccurrence {
            let card = occurrence.card
            let question = card.question
            VStack(spacing: 0) {
                HStack {
                    Button { session.goBack() } label: { Image(systemName: "chevron.backward") }
                        .buttonStyle(.borderless).disabled(!session.canGoBack).help("Назад по истории сессии")
                    Button { session.goForward() } label: { Image(systemName: "chevron.forward") }
                        .buttonStyle(.borderless).disabled(!session.canGoForward).help("Вперёд по истории сессии")
                    Text("\(session.position) из \(session.queue.count)").monospacedDigit().foregroundStyle(.secondary)
                    ProgressView(value: Double(session.position - 1), total: Double(max(1, session.queue.count))).frame(maxWidth: 360)
                    Spacer()
                    if session.totalRounds > 1 {
                        Text("Круг \(session.currentRound) из \(session.totalRounds)").font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(.quaternary, in: Capsule())
                    }
                    if session.isViewingHistory {
                        Button("К текущему") { session.returnToFrontier() }.buttonStyle(.borderless)
                    }
                    Text(store.progressFor(question).state.title).font(.caption).padding(.horizontal, 9).padding(.vertical, 5).background(.quaternary, in: Capsule())
                    Button("Завершить") { onFinish() }.buttonStyle(.borderless)
                }.padding(.horizontal, 24).padding(.vertical, 12).background(.bar)

                QuestionInteractionView(occurrence: occurrence, isHistorical: session.isViewingHistory, onOutcome: { outcome, optionId in
                    let previousState = store.progressFor(question).state
                    let updated = store.record(outcome, for: question, reason: card.reason)
                    session.record(outcome, selectedOptionId: optionId, previousState: previousState, newState: updated.state)
                }, onConceptUnclear: { id in
                    session.markConceptUnclear(id)
                }, onNext: {
                    session.advance()
                    if session.dynamicallyReconsidersSmartQueue, session.smartRefreshLength > 0 {
                        session.reconsiderSmartQueue(with: store.smartCards(length: session.smartRefreshLength))
                    }
                })
                .id(occurrence.id)
            }
        }
    }

    private func reviewMistakes() {
        let questions = store.questions(for: session.summary.mistakeQuestionIDs).shuffled()
        guard !questions.isEmpty else { return }
        session = StudySession(questions: questions, reason: .sessionMistake, randomizeOptions: store.settings.randomizeOptions)
    }

    private func reviewWeak() {
        let questions = store.questions.filter { let value = store.progressFor($0); return value.state == .weak || value.manuallyMarkedHard }
        guard !questions.isEmpty else { return }
        session = StudySession(questions: questions, drillWeak: true, randomizeOptions: store.settings.randomizeOptions)
    }

    private func continueSmart() {
        let cards = store.smartCards(length: store.settings.defaultSessionLength)
        guard !cards.isEmpty else { onFinish(); return }
        session = StudySession(cards: cards, dynamicallyReconsidersSmartQueue: true, randomizeOptions: store.settings.randomizeOptions)
    }
}

struct QuestionInteractionView: View {
    @EnvironmentObject private var store: AppStore
    let occurrence: StudyOccurrence
    let isHistorical: Bool
    let onOutcome: (AttemptOutcome, String?) -> Void
    let onConceptUnclear: (String) -> Void
    let onNext: () -> Void
    @State private var selectedGlossary: GlossaryEntry?
    @State private var note = ""
    @State private var personalDraft: PersonalGlossaryEntry?
    private var reading: ReadingSize { store.settings.readingSize }
    private var question: Question { occurrence.card.question }
    private var displayedOptions: [QuestionOption] { occurrence.displayedOptions }
    private var selectedOptionId: String? { occurrence.selectedOptionId }
    private var outcome: AttemptOutcome? { occurrence.outcome }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("№ \(question.examNumber)", systemImage: "number").font(.callout.bold())
                    Text(question.topic).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { store.toggleBookmark(question) } label: { Label("Закладка", systemImage: store.progressFor(question).bookmarked ? "bookmark.fill" : "bookmark") }
                        .keyboardShortcut("b", modifiers: [])
                    Button { store.toggleHard(question) } label: { Label("Сложный", systemImage: store.progressFor(question).manuallyMarkedHard ? "flame.fill" : "flame") }
                    Button { personalDraft = PersonalGlossaryEntry(term: "", relatedQuestionIDs: [question.id]) } label: { Label("В мой словарь", systemImage: "plus.rectangle.on.rectangle") }
                }
                Text(question.stem).font(.system(size: reading.questionFontSize, weight: .semibold)).textSelection(.enabled)
                FigureView(asset: question.figureAsset)
                if question.teachingDiagramAsset != question.figureAsset { FigureView(asset: question.teachingDiagramAsset) }

                VStack(spacing: 10) {
                    ForEach(Array(displayedOptions.enumerated()), id: \.element.id) { index, option in
                        answerButton(option: option, index: index)
                    }
                }

                if outcome == nil {
                    HStack {
                        Button("Не знаю") { answer(.dontKnow, optionId: nil) }
                            .buttonStyle(.borderedProminent).tint(.orange).keyboardShortcut("d", modifiers: [])
                        Button("Объяснить") { answer(.revealedBeforeAnswer, optionId: nil) }
                            .buttonStyle(.bordered).keyboardShortcut("e", modifiers: [])
                        Spacer()
                        Text("Клавиши 1–4 · D · E · B").font(.caption).foregroundStyle(.tertiary)
                    }
                } else {
                    FeedbackBanner(outcome: outcome!, question: question)
                    ExplanationView(question: question, selectedOptionId: selectedOptionId, onGlossary: { selectedGlossary = $0 })
                    MistakeReasonBar(question: question, visible: outcome != .correct)
                    notes
                    if !isHistorical {
                        Button("Следующий вопрос") { onNext() }
                            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: [])
                    }
                }
                SourceView(question: question)
            }.padding(28).frame(maxWidth: reading.contentMaxWidth, alignment: .leading)
        }
        .onAppear {
            note = store.progressFor(question).note
        }
        .sheet(item: $selectedGlossary) { term in
            GlossaryCard(entry: term, onMarkedUnclear: { onConceptUnclear(term.id) })
        }
        .sheet(item: $personalDraft) { entry in
            PersonalGlossaryEditor(entry: entry, isNew: true)
        }
    }

    @ViewBuilder
    private func answerButton(option: QuestionOption, index: Int) -> some View {
        let isCorrect = option.id == question.correctOptionId
        let selected = selectedOptionId == option.id
        Button {
            guard outcome == nil else { return }
            answer(isCorrect ? .correct : .incorrect, optionId: option.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)").font(.callout.bold()).frame(width: 25, height: 25).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Text(option.text).font(.system(size: reading.answerFontSize)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                if outcome != nil && isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else if outcome != nil && selected { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
            }.padding(reading.answerPadding)
                .background(background(isCorrect: isCorrect, selected: selected), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(border(isCorrect: isCorrect, selected: selected), lineWidth: selected || (outcome != nil && isCorrect) ? 2 : 1))
        }.buttonStyle(.plain).disabled(outcome != nil)
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
    }

    private func background(isCorrect: Bool, selected: Bool) -> Color {
        guard outcome != nil else { return Color.primary.opacity(0.045) }
        if isCorrect { return .green.opacity(0.12) }
        if selected { return .red.opacity(0.12) }
        return Color.primary.opacity(0.045)
    }
    private func border(isCorrect: Bool, selected: Bool) -> Color {
        guard outcome != nil else { return .secondary.opacity(0.2) }
        if isCorrect { return .green }
        if selected { return .red }
        return .secondary.opacity(0.2)
    }

    private func answer(_ value: AttemptOutcome, optionId: String?) {
        guard outcome == nil else { return }
        onOutcome(value, optionId)
    }

    private var notes: some View {
        DisclosureGroup("Личная заметка") {
            TextEditor(text: $note).font(.body).frame(minHeight: 75).padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: note) { _, value in store.updateNote(value, for: question) }
        }
    }
}

struct FeedbackBanner: View {
    @EnvironmentObject private var store: AppStore
    let outcome: AttemptOutcome
    let question: Question
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: outcome == .correct ? "checkmark.circle.fill" : "lightbulb.fill").font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text("Ответ экзаменационного банка: \(question.officialCorrectAnswerText)").font(.system(size: store.settings.readingSize.explanationFontSize))
            }
        }.foregroundStyle(outcome == .correct ? .green : .orange).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background((outcome == .correct ? Color.green : Color.orange).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    private var title: String {
        switch outcome { case .correct: "Верно"; case .incorrect: "Пока неверно"; case .dontKnow: "Хорошо, что сказали честно"; case .revealedBeforeAnswer: "Сначала разберём объяснение" }
    }
}

struct ExplanationView: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    var selectedOptionId: String? = nil
    var onGlossary: ((GlossaryEntry) -> Void)? = nil
    @State private var layer = 0
    private var terms: [GlossaryEntry] { question.glossaryTerms.compactMap { id in store.glossary.first(where: { $0.id == id }) } }
    private var wrongOptions: [QuestionOption] {
        question.options
            .filter { $0.id != question.correctOptionId }
            .sorted { lhs, rhs in
                if lhs.id == selectedOptionId { return true }
                if rhs.id == selectedOptionId { return false }
                return lhs.id < rhs.id
            }
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Слой", selection: $layer) { Text("Кратко").tag(0); Text("С нуля").tag(1); Text("Почему").tag(2); Text("Другие ответы").tag(3) }
                    .pickerStyle(.segmented).labelsHidden()
                if layer == 3 {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(wrongOptions) { option in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(option.text).font(.system(size: store.settings.readingSize.answerFontSize, weight: .semibold))
                                    Spacer()
                                    if option.id == selectedOptionId { Text("Ваш ответ").font(.caption.bold()).foregroundStyle(.red) }
                                }
                                Text(question.wrongOptionExplanations[option.id] ?? "")
                                    .font(.system(size: store.settings.readingSize.explanationFontSize))
                                    .lineSpacing(4)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(option.id == selectedOptionId ? Color.red.opacity(0.08) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(option.id == selectedOptionId ? Color.red.opacity(0.45) : Color.secondary.opacity(0.15)))
                        }
                    }
                } else {
                    Text(layerText).font(.system(size: store.settings.readingSize.explanationFontSize)).textSelection(.enabled).lineSpacing(4)
                }
                if !terms.isEmpty {
                    Divider()
                    Text("Термины").font(.caption.bold()).foregroundStyle(.secondary)
                    FlowLayout(spacing: 7) {
                        ForEach(terms) { term in Button(term.term) { onGlossary?(term) }.buttonStyle(.bordered).controlSize(.small) }
                    }
                }
                Label(question.memoryHint, systemImage: "brain.head.profile").font(.callout).foregroundStyle(.secondary)
                if let note = question.legalHistoricalNote {
                    VStack(alignment: .leading, spacing: 3) { Text("Примечание для реальной практики").font(.caption.bold()); Text(note).font(.callout) }
                        .padding(10).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(7)
        } label: { Label("Объяснение", systemImage: "lightbulb") }
        .onAppear {
            layer = switch store.settings.explanationStyle {
            case "С нуля": 1
            case "Подробно": 2
            default: 0
            }
            if CommandLine.arguments.contains("--snapshot-other-answers") { layer = 3 }
        }
    }
    private var layerText: String {
        switch layer {
        case 0: question.explanationShort
        case 1: question.explanationBeginner
        case 2: question.explanationReasoning
        default: ""
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

struct GlossaryCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let entry: GlossaryEntry
    var onMarkedUnclear: (() -> Void)? = nil
    @State private var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: "character.book.closed.fill").foregroundStyle(.tint); Text(entry.term).font(.title.bold()); Spacer(); Button("Готово") { dismiss() } }
            Text(entry.shortDefinition).font(.title3)
            FigureView(asset: entry.diagramAsset)
            Text(entry.fromZero)
            Label(entry.radioExample, systemImage: "radio").foregroundStyle(.secondary)
            TextField("Личная заметка", text: $note).textFieldStyle(.roundedBorder)
                .onChange(of: note) { _, value in store.updateConceptNote(value, id: entry.id) }
            HStack {
                Button("Пока не понимаю") { store.markConceptWeak(entry.id); onMarkedUnclear?(); dismiss() }
                    .buttonStyle(.borderedProminent).tint(.orange)
                Button("Понял") { store.markConceptUnderstood(entry.id); dismiss() }.buttonStyle(.bordered)
            }
        }.padding(30).frame(width: 660)
            .onAppear { note = store.conceptProgressFor(entry.id).personalNotes }
    }
}

struct MistakeReasonBar: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    let visible: Bool
    @State private var selected: MistakeReason?
    var body: some View {
        if visible {
            VStack(alignment: .leading, spacing: 8) {
                Text("Что помешало? (необязательно)").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(MistakeReason.allCases) { reason in
                        Button(reason.rawValue) { selected = reason; store.tagMistake(reason, question: question) }
                            .buttonStyle(.bordered).controlSize(.small).tint(selected == reason ? .accentColor : .secondary)
                    }
                }
            }
        }
    }
}

struct SessionSummaryView: View {
    @EnvironmentObject private var store: AppStore
    let summary: SessionSummary
    let onReviewMistakes: () -> Void
    let onReviewWeak: () -> Void
    let onContinueSmart: () -> Void
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(.green)
            Text("Сессия завершена").font(.largeTitle.bold())
            HStack(spacing: 12) {
                StatCard(title: "Верно", value: summary.correct, icon: "checkmark", tint: .green)
                StatCard(title: "Ошибки", value: summary.incorrect, icon: "xmark", tint: .red)
                StatCard(title: "Не знаю", value: summary.dontKnow, icon: "questionmark", tint: .orange)
                StatCard(title: "Подсмотрено", value: summary.revealed, icon: "eye", tint: .purple)
            }.frame(maxWidth: 850)
            HStack(spacing: 18) {
                Label("Ослабли: \(summary.becameWeak)", systemImage: "arrow.down.circle")
                Label("Улучшились: \(summary.improved)", systemImage: "arrow.up.circle")
                Label("Освоены: \(summary.mastered)", systemImage: "checkmark.seal")
            }.foregroundStyle(.secondary)
            if let hard = summary.topics.max(by: { $0.value < $1.value }) { Text("Больше всего внимания потребовала тема «\(hard.key)».").foregroundStyle(.secondary) }
            if !summary.unclearConceptIDs.isEmpty {
                Text("Отмечены непонятными: \(summary.unclearConceptIDs.compactMap { id in store.glossary.first(where: { $0.id == id })?.term }.joined(separator: ", ")).")
                    .foregroundStyle(.secondary)
            }
            Text("Ошибки уже запланированы по глобальному счётчику. Повтор появится только после нужного числа других карточек.").foregroundStyle(.secondary)
            HStack {
                Button("Разобрать ошибки этой сессии", action: onReviewMistakes).buttonStyle(.borderedProminent).disabled(summary.mistakeQuestionIDs.isEmpty)
                Button("Повторить слабые", action: onReviewWeak).buttonStyle(.bordered)
                Button("Продолжить умную учёбу", action: onContinueSmart).buttonStyle(.bordered)
                Button("Закрыть", action: onClose).buttonStyle(.borderless)
            }.controlSize(.large)
        }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MockExamView: View {
    @EnvironmentObject private var store: AppStore
    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var answers: [String: String] = [:]
    @State private var displayed: [QuestionOption] = []
    @State private var finished = false
    @State private var result: MockExamResult?

    var body: some View {
        Group {
            if questions.isEmpty { intro }
            else if finished { results }
            else { exam }
        }.onAppear { prepareSnapshotIfNeeded() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 46)).foregroundStyle(.tint)
            Text("Пробный экзамен").font(.largeTitle.bold())
            Text("25 уникальных случайных вопросов из банка третьей категории. Проходной результат — 20 из 25. Объяснения откроются только после завершения.").font(.title3).foregroundStyle(.secondary).frame(maxWidth: 650)
            Button("Начать экзамен") { questions = MockExamBuilder().makeExam(from: store.questions); loadOptions() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }.padding(38).frame(maxWidth: .infinity, alignment: .leading).navigationTitle("Пробный экзамен")
    }

    private var exam: some View {
        let question = questions[index]
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Вопрос \(index + 1) из \(MockExamBuilder.questionCount)").monospacedDigit(); ProgressView(value: Double(index + 1), total: Double(MockExamBuilder.questionCount)).frame(maxWidth: 340); Spacer(); Button("Завершить досрочно") { finish() } }
                Text("№ \(question.examNumber)").font(.callout).foregroundStyle(.secondary)
                Text(question.stem).font(.system(size: store.settings.readingSize.questionFontSize, weight: .bold))
                FigureView(asset: question.figureAsset)
                if question.teachingDiagramAsset != question.figureAsset { FigureView(asset: question.teachingDiagramAsset) }
                ForEach(Array(displayed.enumerated()), id: \.element.id) { optionIndex, option in
                    Button {
                        answers[question.id] = option.id
                        if index == questions.count - 1 { finish() } else { index += 1; loadOptions() }
                    } label: {
                        HStack { Text("\(optionIndex + 1)").font(.callout.bold()).frame(width: 24); Text(option.text).font(.system(size: store.settings.readingSize.answerFontSize)).frame(maxWidth: .infinity, alignment: .leading) }.padding(store.settings.readingSize.answerPadding)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                    }.buttonStyle(.plain).keyboardShortcut(KeyEquivalent(Character(String(optionIndex + 1))), modifiers: [])
                }
            }.padding(30).frame(maxWidth: store.settings.readingSize.contentMaxWidth, alignment: .leading)
        }
    }

    private var results: some View {
        let currentResult = result ?? MockExamBuilder().grade(questions: questions, answers: answers)
        let incorrectIDs = Set(currentResult.incorrectQuestionIDs)
        let failed = questions.filter { incorrectIDs.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(currentResult.correct >= MockExamBuilder.passingScore ? "Экзамен сдан" : "Нужно ещё немного практики").font(.largeTitle.bold()).foregroundStyle(currentResult.correct >= MockExamBuilder.passingScore ? .green : .orange)
                Text("\(currentResult.correct) / \(MockExamBuilder.questionCount)").font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Проходной результат: \(MockExamBuilder.passingScore) / \(MockExamBuilder.questionCount)").foregroundStyle(.secondary)
                HStack {
                    Label("Отвечено: \(currentResult.answered)", systemImage: "checklist")
                    Label("Без ответа: \(currentResult.unansweredQuestionIDs.count)", systemImage: "minus.circle")
                }.foregroundStyle(.secondary)
                Divider()
                Text(failed.isEmpty ? "Ошибок в отправленных ответах нет" : "Разбор отправленных ошибок").font(.title2.bold())
                ForEach(failed) { question in
                    DisclosureGroup("№ \(question.examNumber)  \(question.stem)") {
                        VStack(alignment: .leading, spacing: 8) { Text("Ответ банка: \(question.officialCorrectAnswerText)").bold(); Text(question.explanationShort) }.padding(.vertical, 8)
                    }
                }
                Button("Новый экзамен") { questions = []; answers = [:]; index = 0; finished = false; result = nil }.buttonStyle(.borderedProminent)
            }.padding(30).frame(maxWidth: store.settings.readingSize.contentMaxWidth, alignment: .leading)
        }
    }

    private func loadOptions() { guard index < questions.count else { return }; displayed = store.settings.randomizeOptions ? questions[index].options.shuffled() : questions[index].options }
    private func prepareSnapshotIfNeeded() {
        guard let argumentIndex = CommandLine.arguments.firstIndex(of: "--snapshot-mode"), CommandLine.arguments.indices.contains(argumentIndex + 1) else { return }
        let mode = CommandLine.arguments[argumentIndex + 1]
        guard mode == "mock-question" || mode == "mock-results", questions.isEmpty else { return }
        questions = MockExamBuilder().makeExam(from: store.questions)
        loadOptions()
        if mode == "mock-results" {
            for question in questions.prefix(MockExamBuilder.passingScore) { answers[question.id] = question.correctOptionId }
            finish()
        }
    }
    private func finish() {
        guard !finished else { return }
        finished = true
        result = store.finishMockExam(questions: questions, answers: answers)
    }
}

import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, smart, weak, topics, mock, all, glossary, statistics, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Обзор"
        case .smart: "Умная учёба"
        case .weak: "Слабые вопросы"
        case .topics: "Темы"
        case .mock: "Пробный экзамен"
        case .all: "Вопросы"
        case .glossary: "Словарь"
        case .statistics: "Статистика"
        case .settings: "Настройки"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .smart: "sparkles"
        case .weak: "waveform.path.ecg"
        case .topics: "books.vertical"
        case .mock: "checklist"
        case .all: "list.number"
        case .glossary: "character.book.closed"
        case .statistics: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var store: AppStore
    @State private var section: AppSection? = .dashboard

    init() {
        if let index = CommandLine.arguments.firstIndex(of: "--section"), CommandLine.arguments.indices.contains(index + 1), let value = AppSection(rawValue: CommandLine.arguments[index + 1]) {
            _section = State(initialValue: value)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationTitle(CategoryProfile.productName)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            Group {
                switch section ?? .dashboard {
                case .dashboard: DashboardView(section: $section)
                case .smart: SmartStudyView()
                case .weak: WeakQuestionsView()
                case .topics: TopicsView()
                case .mock: MockExamView()
                case .all: QuestionBrowserView()
                case .glossary: GlossaryView()
                case .statistics: StatisticsView()
                case .settings: SettingsView()
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: .startSmartStudy)) { _ in section = .smart }
        .onReceive(NotificationCenter.default.publisher(for: .openSearch)) { _ in section = .all }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var section: AppSection?

    private func count(_ state: LearningState) -> Int { store.progress.values.filter { $0.state == state }.count }
    private var unseen: Int { store.questions.count - store.progress.values.filter { $0.state != .unseen }.count }
    private var due: Int { store.questions.filter(store.isDue).count }
    private var accuracy: Int {
        let attempts = store.progress.values.reduce(0) { $0 + $1.correctCount + $1.incorrectCount + $1.dontKnowCount + $1.revealedCount }
        let correct = store.progress.values.reduce(0) { $0 + $1.correctCount }
        return attempts == 0 ? 0 : Int((Double(correct) / Double(attempts) * 100).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Добро пожаловать").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Подготовка к экзамену третьей категории — полностью офлайн").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Начать умную сессию") { section = .smart }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    StatCard(title: "Освоено", value: count(.mastered), icon: "checkmark.seal.fill", tint: .green)
                    StatCard(title: "Повторить сейчас", value: due, icon: "arrow.triangle.2.circlepath", tint: .orange)
                    StatCard(title: "Слабые", value: count(.weak), icon: "waveform.path.ecg", tint: .red)
                    StatCard(title: "Не изучены", value: unseen, icon: "circle.dashed", tint: .blue)
                    StatCard(title: "Точность", value: accuracy, suffix: "%", icon: "scope", tint: .purple)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Text("Путь к готовности").font(.headline); Spacer(); Text("\(count(.mastered)) / \(CategoryProfile.bankCount)").monospacedDigit().foregroundStyle(.secondary) }
                        ProgressView(value: Double(count(.mastered)), total: Double(CategoryProfile.bankCount)).tint(.accentColor)
                        Text("Освоенным вопрос становится после успешных повторений, разделённых другими карточками.")
                            .font(.callout).foregroundStyle(.secondary)
                    }.padding(8)
                }

                WeakTopicsPanel()
            }.padding(30).frame(maxWidth: 1100, alignment: .leading)
        }.navigationTitle("Обзор")
    }
}

struct StatCard: View {
    let title: String
    let value: Int
    var suffix = ""
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            Text("\(value)\(suffix)").font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            Text(title).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}

struct WeakTopicsPanel: View {
    @EnvironmentObject private var store: AppStore
    private var topics: [(String, Int)] {
        Dictionary(grouping: store.questions.filter { store.progressFor($0).state == .weak }, by: \.topic)
            .map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(5).map { $0 }
    }
    var body: some View {
        GroupBox("Темы, которым нужна помощь") {
            if topics.isEmpty {
                ContentUnavailableView("Пока нет слабых тем", systemImage: "leaf", description: Text("После первых ответов здесь появятся полезные подсказки."))
                    .frame(height: 150)
            } else {
                VStack(spacing: 12) {
                    ForEach(topics, id: \.0) { topic, count in
                        HStack { Text(topic); Spacer(); Text("\(count)").monospacedDigit().foregroundStyle(.secondary) }
                    }
                }.padding(8)
            }
        }
    }
}

struct WeakQuestionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var session: StudySession?
    @State private var filter: WeakQuestionFilter = .all
    @State private var rounds = 1
    private var allWeak: [Question] {
        store.questions.filter { let progress = store.progressFor($0); return progress.state == .weak || progress.manuallyMarkedHard }
    }
    private var weak: [Question] {
        store.questions.filter { filter.matches(store.progressFor($0)) }
    }
    var body: some View {
        Group {
            if let session { StudyRunnerView(session: session, onFinish: { self.session = nil }) }
            else {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Слабые вопросы").font(.largeTitle.bold())
                    Text("Отдельная тренировка может повторять трудные вопросы чаще. В обычной сессии действует строгий лимит повторов.").foregroundStyle(.secondary)
                    Picker("Фильтр", selection: $filter) {
                        ForEach(WeakQuestionFilter.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("Круги")
                        Picker("Круги", selection: $rounds) {
                            ForEach([1, 3, 5], id: \.self) { Text("\($0)").tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                        Text("Каждый вопрос появится один раз в каждом круге.").font(.callout).foregroundStyle(.secondary)
                    }
                    if weak.isEmpty {
                        ContentUnavailableView(
                            allWeak.isEmpty && filter == .all ? "Слабых вопросов пока нет" : "В этом фильтре вопросов нет",
                            systemImage: allWeak.isEmpty && filter == .all ? "checkmark.circle" : "line.3.horizontal.decrease.circle",
                            description: Text(allWeak.isEmpty && filter == .all ? "Они появятся после ошибок, «Не знаю» или ручной отметки." : "Выберите другой фильтр или продолжите учёбу.")
                        )
                        .frame(maxWidth: 700)
                        .frame(height: 220, alignment: .topLeading)
                    } else {
                        Button("Тренировать \(weak.count * rounds) карточек") {
                            session = StudySession(
                                intensiveQuestions: weak,
                                rounds: rounds,
                                randomizeOptions: store.settings.randomizeOptions
                            )
                        }.buttonStyle(.borderedProminent)
                        List(weak) { q in QuestionRow(question: q) }
                    }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.navigationTitle("Слабые вопросы")
    }
}

struct TopicsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTopic: String?
    @State private var session: StudySession?
    private var topics: [(String, [Question])] {
        Dictionary(grouping: store.questions, by: \.topic)
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        Group {
            if let session { StudyRunnerView(session: session, onFinish: { self.session = nil }) }
            else {
                NavigationSplitView {
                    List(topics, id: \.0, selection: $selectedTopic) { topic, questions in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic).font(.headline)
                                Text("\(questions.count) вопросов").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .tag(topic)
                        .padding(.vertical, 6)
                    }
                    .navigationTitle("Темы")
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 430)
                } detail: {
                    if let selectedTopic,
                       let questions = topics.first(where: { $0.0 == selectedTopic })?.1 {
                        TopicReferenceView(topic: selectedTopic, questions: questions) {
                            session = StudySession(questions: questions, randomizeOptions: store.settings.randomizeOptions)
                        }
                    } else {
                        ContentUnavailableView("Выберите тему", systemImage: "books.vertical", description: Text("Откроется быстрый список вопросов с правильными ответами."))
                    }
                }
            }
        }
    }
}

struct TopicReferenceView: View {
    @EnvironmentObject private var store: AppStore
    let topic: String
    let questions: [Question]
    let train: () -> Void
    @State private var query = ""

    private var filtered: [Question] {
        questions.sorted { $0.examNumber < $1.examNumber }.filter { $0.matchesReferenceQuery(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(topic).font(.largeTitle.bold())
                        Text("\(questions.count) вопросов · ответы видны сразу").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Тренировать тему", action: train).buttonStyle(.borderedProminent).controlSize(.large)
                }
                TextField("Номер, вопрос или ответ", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 560)
                ForEach(filtered) { question in
                    TopicQuestionReferenceRow(question: question)
                }
            }
            .padding(28)
            .frame(maxWidth: store.settings.readingSize.contentMaxWidth, alignment: .leading)
        }
        .navigationTitle(topic)
    }
}

struct TopicQuestionReferenceRow: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    @State private var expanded: Bool

    init(question: Question, initiallyExpanded: Bool = false) {
        self.question = question
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text("№ \(question.examNumber)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                    Text(question.stem).font(.system(size: store.settings.readingSize.metadataFontSize, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            Text("Ответ: \(question.officialCorrectAnswerText)")
                .font(.system(size: store.settings.readingSize.answerFontSize, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.leading, 70)
            if !question.explanationShort.isEmpty {
                Text(question.explanationShort).font(.callout).foregroundStyle(.secondary).padding(.leading, 70)
            }
            if expanded {
                Divider().padding(.leading, 70)
                VStack(alignment: .leading, spacing: 14) {
                    FigureView(asset: question.figureAsset)
                    if question.teachingDiagramAsset != question.figureAsset { FigureView(asset: question.teachingDiagramAsset) }
                    ReferenceDetailsView(question: question, includeOptions: true)
                }.padding(.leading, 70)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

struct QuestionRow: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("№ \(question.examNumber)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Text(question.stem).font(.system(size: store.settings.readingSize.metadataFontSize)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if store.progressFor(question).bookmarked { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint) }
        }.padding(.vertical, 4)
    }
}

enum QuestionBrowserFilter: String, CaseIterable, Identifiable {
    case all, unseen, due, weak, incorrectBefore, bookmarked
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Все"
        case .unseen: "Не изучены"
        case .weak: "Слабые"
        case .due: "Пора повторить"
        case .bookmarked: "Закладки"
        case .incorrectBefore: "Были ошибки"
        }
    }
}

struct QuestionBrowserView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var stateFilter: QuestionBrowserFilter = .all
    @State private var selected: Question?
    @FocusState private var searchFocused: Bool
    private var filtered: [Question] {
        store.questions.filter { question in
            let progress = store.progressFor(question)
            let stateOK: Bool = switch stateFilter {
            case .all: true
            case .unseen: progress.state == .unseen
            case .weak: progress.state == .weak || progress.manuallyMarkedHard
            case .due: store.isDue(question)
            case .bookmarked: progress.bookmarked
            case .incorrectBefore: progress.incorrectCount > 0
            }
            guard stateOK, !query.isEmpty else { return stateOK }
            let terms = question.glossaryTerms.compactMap { id in store.glossary.first(where: { $0.id == id })?.term }.joined(separator: " ")
            let content = "\(question.examNumber) \(question.stem) \(question.options.map(\.text).joined(separator: " ")) \(question.explanationShort) \(question.topic) \(terms) \(progress.note)"
            return content.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Вопрос, ответ, тема или термин", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                    Picker("Состояние", selection: $stateFilter) {
                        ForEach(QuestionBrowserFilter.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 175)
                }.padding()
                List(filtered, selection: $selected) { q in QuestionRow(question: q).tag(q) }
            }.navigationTitle("Вопросы — \(filtered.count)")
                .navigationSplitViewColumnWidth(min: 400, ideal: 480, max: 620)
        } detail: {
            if let selected { QuestionDetailView(question: selected) }
            else { ContentUnavailableView("Выберите вопрос", systemImage: "list.number") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSearch)) { _ in searchFocused = true }
    }
}

struct QuestionDetailView: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Вопрос № \(question.examNumber)").font(.title2.bold())
                        Text(question.topic).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.toggleBookmark(question) } label: {
                        Label(store.progressFor(question).bookmarked ? "В закладках" : "Закладка", systemImage: store.progressFor(question).bookmarked ? "bookmark.fill" : "bookmark")
                    }
                    Button { store.toggleHard(question) } label: {
                        Label(store.progressFor(question).manuallyMarkedHard ? "Сложный" : "Отметить сложным", systemImage: store.progressFor(question).manuallyMarkedHard ? "flag.fill" : "flag")
                    }
                }
                Text(question.stem).font(.system(size: store.settings.readingSize.questionFontSize, weight: .semibold))
                FigureView(asset: question.figureAsset)
                if question.teachingDiagramAsset != question.figureAsset { FigureView(asset: question.teachingDiagramAsset) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Правильный ответ").font(.callout).foregroundStyle(.secondary)
                        Text(question.officialCorrectAnswerText).font(.system(size: store.settings.readingSize.answerFontSize, weight: .bold)).foregroundStyle(.tint)
                        Text(question.explanationShort).font(.system(size: store.settings.readingSize.explanationFontSize))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                ReferenceDetailsView(question: question, includeOptions: true)
                DisclosureGroup("Личная заметка") {
                    QuestionNoteEditor(question: question)
                }
                DisclosureGroup("Источник и примечания") { SourceView(question: question).padding(.top, 8) }
            }.padding(28).frame(maxWidth: store.settings.readingSize.contentMaxWidth, alignment: .leading)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ReferenceDetailsView: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    let includeOptions: Bool

    private var glossaryEntries: [GlossaryEntry] {
        question.glossaryTerms.compactMap { id in store.glossary.first(where: { $0.id == id }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if includeOptions {
                DisclosureGroup("Показать все варианты") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(question.options) { option in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: option.id == question.correctOptionId ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(option.id == question.correctOptionId ? .green : .secondary)
                                Text(option.text)
                            }
                        }
                    }.padding(.top, 8)
                }
            }
            DisclosureGroup("С нуля") {
                Text(question.explanationBeginner).font(.system(size: store.settings.readingSize.explanationFontSize)).padding(.top, 8)
            }
            DisclosureGroup("Почему") {
                Text(question.explanationReasoning).font(.system(size: store.settings.readingSize.explanationFontSize)).padding(.top, 8)
            }
            DisclosureGroup("Другие ответы") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(question.options.filter { $0.id != question.correctOptionId }) { option in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.text).fontWeight(.semibold)
                            Text(question.wrongOptionExplanations[option.id] ?? "").foregroundStyle(.secondary)
                        }
                    }
                }.padding(.top, 8)
            }
            if !glossaryEntries.isEmpty {
                DisclosureGroup("Термины") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(glossaryEntries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.term).fontWeight(.semibold)
                                Text(entry.shortDefinition).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.top, 8)
                }
            }
        }
    }
}

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    private var mostLapses: [(Question, Int)] {
        store.questions.map { ($0, store.progressFor($0).lapseCount) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(10).map { $0 }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Статистика").font(.largeTitle.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))]) {
                    StatCard(title: "Всего попыток", value: store.progress.values.reduce(0) { $0 + $1.attempts }, icon: "cursorarrow.click", tint: .blue)
                    StatCard(title: "Не знаю", value: store.progress.values.reduce(0) { $0 + $1.dontKnowCount }, icon: "questionmark", tint: .orange)
                    StatCard(title: "Пробные экзамены", value: store.mockScores.count, icon: "checklist", tint: .purple)
                }
                GroupBox("Больше всего ошибок") {
                    if mostLapses.isEmpty { Text("Данные появятся после повторений.").foregroundStyle(.secondary).padding() }
                    else { ForEach(mostLapses, id: \.0.id) { q, count in HStack { Text("№ \(q.examNumber)  \(q.stem)").lineLimit(1); Spacer(); Text("\(count)").monospacedDigit() }.padding(.vertical, 4) } }
                }
                GroupBox("Результаты пробных экзаменов") {
                    if store.mockScores.isEmpty { Text("Экзамены ещё не проходились.").foregroundStyle(.secondary).padding() }
                    else { ForEach(store.mockScores.reversed()) { score in HStack { Text(score.date.formatted(date: .abbreviated, time: .shortened)); Text("отвечено: \(score.answered)").font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(score.correct)/\(score.total)").bold().foregroundStyle(score.passed ? .green : .red) }.padding(.vertical, 4) } }
                }
            }.padding(28).frame(maxWidth: 1000, alignment: .leading)
        }.navigationTitle("Статистика")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showReset = false
    var body: some View {
        Form {
            Section("Учёба") {
                Picker("Длина сессии", selection: $store.settings.defaultSessionLength) { ForEach([10, 20, 30, 40], id: \.self) { Text("\($0)").tag($0) } }
                Toggle("Перемешивать варианты ответов", isOn: $store.settings.randomizeOptions)
                Picker("Размер текста", selection: $store.settings.readingSize) {
                    ForEach(ReadingSize.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Объяснение", selection: $store.settings.explanationStyle) { Text("Кратко").tag("Кратко"); Text("С нуля").tag("С нуля"); Text("Подробно").tag("Подробно") }
            }
            Section("Резервная копия") {
                HStack { Button("Экспорт JSON…", action: exportBackup); Button("Импорт JSON…", action: importBackup); Spacer() }
                Text("Прогресс HAM Trainer 3 хранится отдельно: Application Support/HAMTrainer3.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Данные") {
                Button("Сбросить весь прогресс…", role: .destructive) { showReset = true }
            }
            Section("Источник") {
                LabeledContent("Банк", value: "218 вопросов, третья категория")
                LabeledContent("Пробный экзамен", value: "25 вопросов, проходной 20 / 25")
                LabeledContent("Версия схемы данных", value: "3")
                Text("Официальный ответ банка и примечание для реальной практики хранятся отдельно.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Настройки")
            .onChange(of: store.settings) { _, _ in store.saveProgress() }
            .confirmationDialog("Удалить весь учебный прогресс?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Удалить прогресс", role: .destructive) { store.resetProgress() }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Банк вопросов останется на месте. Перед сбросом можно экспортировать JSON.") }
    }

    private func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = CategoryProfile.backupFilename; panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { do { try store.exportBackup(to: url) } catch { store.errorMessage = error.localizedDescription } }
    }
    private func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { do { try store.importBackup(from: url) } catch { store.errorMessage = error.localizedDescription } }
    }
}

struct SourceView: View {
    let question: Question
    var body: some View {
        GroupBox("Источник") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(question.sourceReference.document), стр. \(question.sourceReference.page), вопрос № \(question.sourceReference.sourceQuestionNumber)")
                Text("Пояснение: \(question.sourceReference.explanationDocument), стр. \(question.sourceReference.explanationPage)")
                if let note = question.legalHistoricalNote { Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).padding(.top, 6) }
            }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(5)
        }
    }
}

struct FigureView: View {
    let asset: String?
    @State private var enlarged = false

    var body: some View {
        if let asset, let url = Bundle.studyResources.url(forResource: asset, withExtension: nil, subdirectory: "Content"), let image = NSImage(contentsOf: url) {
            Button { enlarged = true } label: {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: min(max(image.size.width, 420), 980), maxHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
            .buttonStyle(.plain)
            .help("Открыть рисунок крупнее")
            .sheet(isPresented: $enlarged) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable().scaledToFit().frame(minWidth: min(max(image.size.width, 700), 1300))
                        .padding(24)
                }
                .frame(minWidth: 760, minHeight: 560)
            }
        }
    }
}

import SwiftUI

@main
struct HAMTrainerApp: App {
    @StateObject private var store: AppStore

    init() {
        let arguments = CommandLine.arguments
        let snapshot = arguments.contains("--snapshot")
        let persistenceURL: URL? = snapshot
            ? FileManager.default.temporaryDirectory.appendingPathComponent("HAMTrainer3-visual-qa.json")
            : nil
        if let persistenceURL { try? FileManager.default.removeItem(at: persistenceURL) }
        let value = AppStore(persistenceURL: persistenceURL)
        if let index = arguments.firstIndex(of: "--text-size"), arguments.indices.contains(index + 1) {
            value.settings.readingSize = switch arguments[index + 1] {
            case "regular": .regular
            case "extra-large": .extraLarge
            default: .large
            }
        }
        if let index = arguments.firstIndex(of: "--snapshot-mode"), arguments.indices.contains(index + 1),
           arguments[index + 1] == "weak-populated" {
            for number in [173, 180] {
                if let question = value.questions.first(where: { $0.examNumber == number }) {
                    _ = value.record(.incorrect, for: question, reason: .manuallySelected)
                    value.toggleHard(question)
                }
            }
        }
        _store = StateObject(wrappedValue: value)
    }

    var body: some Scene {
        WindowGroup(CategoryProfile.productName) {
            SnapshotRootView()
                .environmentObject(store)
                .frame(minWidth: 860, minHeight: 620)
                .alert(CategoryProfile.productName, isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                )) { Button("OK") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandMenu("Учёба") {
                Button("Умная сессия") { NotificationCenter.default.post(name: .startSmartStudy, object: nil) }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("Поиск") { NotificationCenter.default.post(name: .openSearch, object: nil) }
                    .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}

struct SnapshotRootView: View {
    @EnvironmentObject private var store: AppStore
    private var snapshotQuestion: Question? {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot-question"), CommandLine.arguments.indices.contains(index + 1), let number = Int(CommandLine.arguments[index + 1]) else { return nil }
        return store.questions.first(where: { $0.examNumber == number })
    }
    private var snapshotGlossary: GlossaryEntry? {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot-glossary"), CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return store.glossary.first(where: { $0.id == CommandLine.arguments[index + 1] })
    }
    private var snapshotColorScheme: ColorScheme? {
        guard CommandLine.arguments.contains("--snapshot") else { return nil }
        guard let index = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1] == "dark" ? .dark : .light
    }
    private var snapshotMode: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot-mode"), CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }
    var body: some View {
        Group {
            if let snapshotMode, snapshotMode.hasPrefix("study-") { StudySnapshotView(mode: snapshotMode) }
            else if snapshotMode == "topic-reference",
                    let group = Dictionary(grouping: store.questions, by: \.topic).max(by: { $0.value.count < $1.value.count }) {
                TopicReferenceView(topic: group.key, questions: group.value, train: {})
            }
            else if snapshotMode == "topic-expanded",
                    let question = store.questions.first(where: { $0.examNumber == 173 }) {
                ScrollView {
                    TopicQuestionReferenceRow(question: question, initiallyExpanded: true)
                        .padding(28)
                        .frame(maxWidth: store.settings.readingSize.contentMaxWidth)
                }
            }
            else if snapshotMode == "other-answers",
                    let question = store.questions.first(where: { $0.examNumber == 173 }) {
                OtherAnswersSnapshotView(question: question)
            }
            else if snapshotMode == "personal-editor" {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                    PersonalGlossaryEditor(entry: PersonalGlossaryEntry(term: "Балун", shortDefinition: "Согласующее устройство"), isNew: true)
                        .frame(width: 680, height: 640)
                }
            }
            else if let snapshotQuestion { QuestionDetailView(question: snapshotQuestion) }
            else if let snapshotGlossary { GlossaryCard(entry: snapshotGlossary) }
            else { MainView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(snapshotColorScheme)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SnapshotCaptureView())
    }
}

private struct OtherAnswersSnapshotView: View {
    @EnvironmentObject private var store: AppStore
    let question: Question

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Другие ответы").font(.largeTitle.bold())
                Text("№ \(question.examNumber) · \(question.stem)").font(.title3).foregroundStyle(.secondary)
                ForEach(question.options.filter { $0.id != question.correctOptionId }) { option in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(option.text).font(.system(size: store.settings.readingSize.answerFontSize, weight: .semibold))
                        Text(question.wrongOptionExplanations[option.id] ?? "")
                            .font(.system(size: store.settings.readingSize.explanationFontSize))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                }
            }.padding(30).frame(maxWidth: store.settings.readingSize.contentMaxWidth, alignment: .leading)
        }
    }
}

private struct StudySnapshotView: View {
    @EnvironmentObject private var store: AppStore
    let mode: String
    @State private var session: StudySession?

    var body: some View {
        Group {
            if let session { StudyRunnerView(session: session, onFinish: {}) }
            else { ProgressView().task { prepare() } }
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private func prepare() {
        let requestedNumber: Int? = {
            guard let index = CommandLine.arguments.firstIndex(of: "--snapshot-question"),
                  CommandLine.arguments.indices.contains(index + 1) else { return nil }
            return Int(CommandLine.arguments[index + 1])
        }()
        guard let first = requestedNumber.flatMap({ number in
                  store.questions.first(where: { $0.examNumber == number })
              }) ?? store.questions.first(where: { $0.examNumber == 173 }),
              let second = store.questions.first(where: { $0.examNumber != first.examNumber }) else { return }
        var value = StudySession(questions: [first, second], randomizeOptions: false)
        if mode != "study-question" {
            let selected = mode == "study-answered" ? first.correctOptionId : first.options.first(where: { $0.id != first.correctOptionId })?.id
            value.record(mode == "study-answered" ? .correct : .incorrect, selectedOptionId: selected, previousState: .unseen, newState: .learning)
        }
        if mode == "study-history" { value.advance(); value.goBack() }
        session = value
    }
}

extension Notification.Name {
    static let startSmartStudy = Notification.Name("startSmartStudy")
    static let openSearch = Notification.Name("openSearch")
}

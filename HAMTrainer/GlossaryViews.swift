import SwiftUI

private enum GlossarySection: String, CaseIterable, Identifiable {
    case review, mine, builtIn
    var id: String { rawValue }
    var title: String {
        switch self {
        case .review: "Повторить"
        case .mine: "Мой словарь"
        case .builtIn: "Встроенный"
        }
    }
}

struct GlossaryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var section: GlossarySection = .review
    @State private var editorEntry: PersonalGlossaryEntry?
    @State private var editingNew = false

    private var builtIn: [GlossaryEntry] {
        store.glossary.filter { entry in
            query.isEmpty || "\(entry.term) \(entry.aliases.joined(separator: " ")) \(entry.shortDefinition) \(entry.fromZero)".localizedCaseInsensitiveContains(query)
        }
    }

    private var personal: [PersonalGlossaryEntry] {
        store.personalGlossary.filter { entry in
            query.isEmpty || "\(entry.term) \(entry.shortDefinition) \(entry.detailedExplanation) \(entry.personalNotes) \(entry.example)".localizedCaseInsensitiveContains(query)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var weak: [GlossaryEntry] {
        builtIn.filter { store.weakConceptIds.contains($0.id) }.sorted {
            store.conceptProgressFor($0.id).unclearCount > store.conceptProgressFor($1.id).unclearCount
        }
    }

    private var learned: [GlossaryEntry] {
        builtIn.filter { store.conceptProgressFor($0.id).isLearned }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Термин, определение или личная заметка", text: $query).textFieldStyle(.roundedBorder)
                Button { newEntry() } label: { Label("Добавить термин", systemImage: "plus") }.buttonStyle(.borderedProminent)
            }.padding()
            Picker("Раздел", selection: $section) {
                ForEach(GlossarySection.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 10)

            List {
                switch section {
                case .review:
                    Section("Термины к повторению — \(weak.count)") {
                        if weak.isEmpty {
                            Text("Отметьте «Пока не понимаю» в карточке термина — он появится здесь.").foregroundStyle(.secondary)
                        } else {
                            ForEach(weak) { BuiltInTermRow(entry: $0) }
                        }
                    }
                    Section("Недавно добавленные") {
                        if personal.isEmpty { Text("Личных терминов пока нет.").foregroundStyle(.secondary) }
                        else { ForEach(personal.prefix(8)) { PersonalTermRow(entry: $0, edit: edit) } }
                    }
                    Section("Изученные — \(learned.count)") {
                        ForEach(learned.prefix(20)) { BuiltInTermRow(entry: $0) }
                    }
                case .mine:
                    Section("Мой словарь — \(personal.count)") {
                        if personal.isEmpty { Text("Добавьте незнакомое слово из вопроса или создайте запись здесь.").foregroundStyle(.secondary) }
                        else { ForEach(personal) { PersonalTermRow(entry: $0, edit: edit) } }
                    }
                case .builtIn:
                    Section("Встроенный словарь — \(builtIn.count)") {
                        ForEach(builtIn) { BuiltInTermRow(entry: $0) }
                    }
                }
            }
        }
        .navigationTitle("Понятия и словарь")
        .sheet(item: $editorEntry) { entry in PersonalGlossaryEditor(entry: entry, isNew: editingNew) }
    }

    private func newEntry() {
        editingNew = true
        editorEntry = PersonalGlossaryEntry(term: query)
    }

    private func edit(_ entry: PersonalGlossaryEntry) {
        editingNew = false
        editorEntry = entry
    }
}

private struct BuiltInTermRow: View {
    @EnvironmentObject private var store: AppStore
    let entry: GlossaryEntry
    @State private var note = ""

    private var relatedQuestions: [Question] {
        store.questions.filter { $0.glossaryTerms.contains(entry.id) }
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.fromZero).font(.system(size: store.settings.readingSize.explanationFontSize))
                Label(entry.radioExample, systemImage: "radio").font(.system(size: store.settings.readingSize.answerFontSize)).foregroundStyle(.secondary)
                if !entry.relatedTerms.isEmpty {
                    Text("Связанные понятия: \(entry.relatedTerms.compactMap { id in store.glossary.first(where: { $0.id == id })?.term }.joined(separator: ", "))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !relatedQuestions.isEmpty {
                    Text("Связанные вопросы: \(relatedQuestions.prefix(12).map { "№ \($0.examNumber)" }.joined(separator: ", "))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                TextField("Личная заметка", text: $note).textFieldStyle(.roundedBorder)
                    .onChange(of: note) { _, value in store.updateConceptNote(value, id: entry.id) }
                HStack {
                    Button("Пока не понимаю") { store.markConceptWeak(entry.id) }.tint(.orange)
                    Button("Понял") { store.markConceptUnderstood(entry.id) }
                }.buttonStyle(.bordered)
            }.padding(.vertical, 8)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.term).font(.headline)
                    Text(entry.shortDefinition).font(.system(size: store.settings.readingSize.metadataFontSize)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                let progress = store.conceptProgressFor(entry.id)
                if progress.unclearCount > 0 && !progress.isLearned {
                    Text("неясно ×\(progress.unclearCount)").font(.caption).foregroundStyle(.orange)
                } else if progress.isLearned {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }.padding(.vertical, 4)
            .onAppear { note = store.conceptProgressFor(entry.id).personalNotes }
    }
}

private struct PersonalTermRow: View {
    let entry: PersonalGlossaryEntry
    let edit: (PersonalGlossaryEntry) -> Void
    var body: some View {
        Button { edit(entry) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.term).font(.headline)
                    Text(entry.shortDefinition.isEmpty ? "Добавьте краткое определение" : entry.shortDefinition).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.vertical, 4)
    }
}

struct PersonalGlossaryEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PersonalGlossaryEntry
    let isNew: Bool

    init(entry: PersonalGlossaryEntry, isNew: Bool) {
        _draft = State(initialValue: entry)
        self.isNew = isNew
    }

    var body: some View {
        Form {
            LabeledContent("Термин") { TextField("Название", text: $draft.term).frame(minWidth: 390) }
            LabeledContent("Краткое определение") { TextField("Одной фразой", text: $draft.shortDefinition).frame(minWidth: 390) }
            LabeledContent("Подробное объяснение") { TextField("Объясните своими словами", text: $draft.detailedExplanation, axis: .vertical).lineLimit(4...9).frame(minWidth: 390) }
            LabeledContent("Пример") { TextField("Пример из радиопрактики", text: $draft.example, axis: .vertical).lineLimit(3...6).frame(minWidth: 390) }
            LabeledContent("Личные заметки") { TextField("Что важно запомнить", text: $draft.personalNotes, axis: .vertical).lineLimit(3...8).frame(minWidth: 390) }
            LabeledContent("Связанные вопросы") { TextField("Например: q-057, q-347", text: relatedIDs).frame(minWidth: 390) }
            HStack {
                if !isNew { Button("Удалить", role: .destructive) { store.deletePersonalGlossaryEntry(id: draft.id); dismiss() } }
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Сохранить") { save() }.buttonStyle(.borderedProminent).disabled(draft.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 680)
    }

    private var relatedIDs: Binding<String> {
        Binding(
            get: { draft.relatedQuestionIDs.joined(separator: ", ") },
            set: { draft.relatedQuestionIDs = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        )
    }

    private func save() {
        draft.term = draft.term.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew {
            var created = store.addPersonalGlossaryEntry(term: draft.term, relatedQuestionIDs: draft.relatedQuestionIDs)
            created.shortDefinition = draft.shortDefinition
            created.detailedExplanation = draft.detailedExplanation
            created.personalNotes = draft.personalNotes
            created.example = draft.example
            store.updatePersonalGlossaryEntry(created)
        } else {
            store.updatePersonalGlossaryEntry(draft)
        }
        dismiss()
    }
}

struct QuestionNoteEditor: View {
    @EnvironmentObject private var store: AppStore
    let question: Question
    @State private var note = ""

    var body: some View {
        TextEditor(text: $note).frame(minHeight: 90)
            .onAppear { note = store.progressFor(question).note }
            .onChange(of: note) { _, value in store.updateNote(value, for: question) }
    }
}

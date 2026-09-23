import SwiftUI

/// Edit a recipe in the app: title, description, times, servings, ingredients, steps, notes and tags.
/// Only changed fields are sent, so Mealie keeps everything the editor doesn't touch.
public struct RecipeEditorView: View {
    let api: any MealieAPI
    let original: Recipe
    let onSaved: (Recipe) -> Void

    @State private var draft: Draft
    @State private var isSaving = false
    @State private var error: String?
    @State private var editingTags = false
    @Environment(\.dismiss) private var dismiss

    public init(recipe: Recipe, api: any MealieAPI, onSaved: @escaping (Recipe) -> Void) {
        self.api = api
        self.original = recipe
        self.onSaved = onSaved
        _draft = State(initialValue: Draft(recipe: recipe))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(L("Rezept")) {
                    TextField(L("Titel"), text: $draft.name)
                        .font(.headline)
                    TextField(L("Beschreibung"), text: $draft.description, axis: .vertical)
                        .lineLimit(1...6)
                }

                Section(L("Angaben")) {
                    HStack {
                        Text(L("Portionen"))
                        Spacer()
                        TextField(L("z. B. 4"), text: $draft.servings)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    LabeledTextField(label: L("Vorbereitung"), placeholder: L("z. B. 10 Minuten"), text: $draft.prepTime)
                    LabeledTextField(label: L("Kochzeit"), placeholder: L("z. B. 25 Minuten"), text: $draft.cookTime)
                    LabeledTextField(label: L("Gesamt"), placeholder: L("z. B. 35 Minuten"), text: $draft.totalTime)
                }

                Section {
                    Button {
                        editingTags = true
                    } label: {
                        HStack {
                            Text(L("Tags"))
                            Spacer()
                            Text(draft.tags.isEmpty ? "keine" : draft.tags.map(\.name).joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                EditableListSection(
                    title: L("Zutaten"),
                    addTitle: L("Zutat hinzufügen"),
                    placeholder: L("z. B. 250 g Mehl"),
                    items: $draft.ingredients
                )

                EditableListSection(
                    title: L("Zubereitung"),
                    addTitle: L("Schritt hinzufügen"),
                    placeholder: L("Was ist zu tun?"),
                    multiline: true,
                    numbered: true,
                    items: $draft.steps
                )

                EditableListSection(
                    title: L("Notizen"),
                    addTitle: L("Notiz hinzufügen"),
                    placeholder: L("Tipp, Variante, Beilage …"),
                    multiline: true,
                    items: $draft.notes
                )
            }
            .navigationTitle(L("Bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen"), systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L("Sichern"), systemImage: "checkmark") { Task { await save() } }
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .sheet(isPresented: $editingTags) {
                TagEditorView(api: api, selection: draft.tags) { tags in
                    draft.tags = tags
                }
            }
            .alert(L("Speichern fehlgeschlagen"), isPresented: .constant(error != nil)) {
                Button(L("OK")) { error = nil }
            } message: {
                Text(error ?? "")
            }
            .interactiveDismissDisabled(draft.hasChanges(from: original))
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await api.updateRecipe(slug: original.slug, changes: draft.patch(from: original))
            onSaved(saved)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Draft

extension RecipeEditorView {
    /// The recipe as plain text fields, which is what the form edits.
    struct Draft {
        var name: String
        var description: String
        var servings: String
        var prepTime: String
        var cookTime: String
        var totalTime: String
        var ingredients: [TextItem]
        var steps: [TextItem]
        var notes: [TextItem]
        var tags: [RecipeTag]

        init(recipe: Recipe) {
            name = recipe.name ?? ""
            description = recipe.description ?? ""
            servings = recipe.servings.map { RecipeFormat.servings($0) } ?? ""
            prepTime = Self.editableDuration(recipe.prepTime)
            cookTime = Self.editableDuration(recipe.cookTime)
            totalTime = Self.editableDuration(recipe.totalTime)
            ingredients = recipe.ingredients.map { TextItem(text: $0.text(), title: $0.title?.nilIfBlank) }
            steps = recipe.instructions.map { TextItem(text: $0.text, title: $0.title?.nilIfBlank) }
            notes = (recipe.notes ?? []).map { TextItem(text: $0.text ?? "", title: $0.title?.nilIfBlank) }
            tags = recipe.tags ?? []
        }

        func hasChanges(from recipe: Recipe) -> Bool {
            let current = Draft(recipe: recipe)
            return name != current.name || description != current.description || servings != current.servings
                || prepTime != current.prepTime || cookTime != current.cookTime || totalTime != current.totalTime
                || ingredients != current.ingredients || steps != current.steps || notes != current.notes
                || tags != current.tags
        }

        /// ISO durations ("PT10M") are shown the way the recipe page shows them ("10 min").
        static func editableDuration(_ raw: String?) -> String {
            guard let raw = raw?.nilIfBlank else { return "" }
            return raw.uppercased().hasPrefix("P") ? RecipeFormat.duration(raw) ?? raw : raw
        }

        /// An untouched time goes back unchanged, so saving doesn't rewrite ISO durations.
        static func storedDuration(_ text: String, original: String?) -> String {
            text == editableDuration(original) ? original ?? "" : text
        }

        /// Builds the patch, keeping structured ingredients (amount, unit, food) whenever their
        /// text was left alone. Edited or new ones go back as plain text for Mealie to display.
        func patch(from recipe: Recipe) -> RecipePatch {
            let originals = recipe.ingredients
            let ingredientPayload: [RecipeIngredient] = ingredients.compactMap { item in
                guard let text = item.text.nilIfBlank else { return nil }
                if let match = originals.first(where: { $0.text() == text }) {
                    var kept = match
                    kept.title = item.title
                    return kept
                }
                return .freeText(text, title: item.title)
            }

            return RecipePatch(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                recipeServings: Double(servings.replacingOccurrences(of: ",", with: ".")) ?? 0,
                prepTime: Self.storedDuration(prepTime, original: recipe.prepTime),
                cookTime: Self.storedDuration(cookTime, original: recipe.cookTime),
                totalTime: Self.storedDuration(totalTime, original: recipe.totalTime),
                recipeIngredient: ingredientPayload,
                recipeInstructions: steps.compactMap { item in
                    item.text.nilIfBlank.map { RecipeStep(id: nil, title: item.title, summary: nil, text: $0) }
                },
                notes: notes.compactMap { item in
                    item.text.nilIfBlank.map { RecipeNote(title: item.title, text: $0) }
                },
                tags: tags
            )
        }
    }

    struct TextItem: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var title: String?

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text && lhs.title == rhs.title }
    }
}

// MARK: - Pieces

private struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }
}

/// A form section of reorderable text rows with add and delete.
private struct EditableListSection: View {
    let title: String
    let addTitle: String
    let placeholder: String
    var multiline = false
    var numbered = false
    @Binding var items: [RecipeEditorView.TextItem]

    @FocusState private var focused: UUID?

    var body: some View {
        Section {
            ForEach($items) { $item in
                HStack(alignment: .top, spacing: 10) {
                    if numbered, let index = items.firstIndex(where: { $0.id == item.id }) {
                        Text("\(index + 1).")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    if multiline {
                        TextField(placeholder, text: $item.text, axis: .vertical)
                            .lineLimit(1...10)
                            .focused($focused, equals: item.id)
                    } else {
                        TextField(placeholder, text: $item.text)
                            .focused($focused, equals: item.id)
                    }
                }
            }
            .onDelete { items.remove(atOffsets: $0) }
            .onMove { items.move(fromOffsets: $0, toOffset: $1) }

            Button(addTitle, systemImage: "plus.circle.fill") {
                let new = RecipeEditorView.TextItem(text: "", title: nil)
                items.append(new)
                focused = new.id
            }
            .foregroundStyle(.brand)
        } header: {
            HStack {
                Text(title)
                Spacer()
                if items.count > 1 {
                    EditButton()
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }
}

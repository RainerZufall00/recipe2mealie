import SwiftUI

/// Keeps the display on while cooking. Only the app provides this; extensions can't control it.
public struct KeepScreenAwakeAction: Equatable {
    private let handler: @MainActor (Bool) -> Void

    public init(_ handler: @escaping @MainActor (Bool) -> Void) { self.handler = handler }

    @MainActor public func callAsFunction(_ enabled: Bool) { handler(enabled) }

    // The action never changes during the app's lifetime.
    public static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension EnvironmentValues {
    @Entry public var keepScreenAwake: KeepScreenAwakeAction? = nil
}

public struct RecipeDetailView: View {
    let slug: String
    let api: any MealieAPI
    let webURL: URL?

    @State private var recipe: Recipe?
    @State private var loadError: String?
    @State private var servings: Double?
    @State private var checkedIngredients: Set<Int> = []
    @State private var doneSteps: Set<Int> = []
    @State private var cookMode = false
    @State private var editing = false

    @Environment(\.keepScreenAwake) private var keepScreenAwake
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(slug: String, api: any MealieAPI, initial: Recipe? = nil, webURL: URL? = nil) {
        self.slug = slug
        self.api = api
        self.webURL = webURL
        _recipe = State(initialValue: initial)
    }

    public var body: some View {
        Group {
            if let recipe {
                content(recipe)
            } else if let loadError {
                ContentUnavailableView(L("Rezept nicht verfügbar"), systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task(id: slug) { await load() }
        .onDisappear { if cookMode { keepScreenAwake?(false) } }
        .sheet(isPresented: $editing) {
            if let recipe {
                RecipeEditorView(recipe: recipe, api: api) { saved in
                    self.recipe = saved
                    servings = nil
                    checkedIngredients = []
                    doneSteps = []
                }
                // A long form; on iPad the default form sheet cuts most of it off.
                .presentationSizing(.page)
            }
        }
    }

    // MARK: Content

    private func content(_ recipe: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(recipe)

                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 32) {
                        ingredients(recipe).frame(maxWidth: 360)
                        instructions(recipe)
                    }
                } else {
                    ingredients(recipe)
                    instructions(recipe)
                }

                notes(recipe)
                links(recipe)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await load() }
    }

    private func header(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RecipeImage(url: api.imageURL(for: recipe, size: .original), cornerRadius: 28)
                .frame(height: recipe.hasImage ? (sizeClass == .regular ? 380 : 260) : 160)
                .overlay(alignment: .bottomTrailing) {
                    CoverImageMenu(recipe: recipe, api: api, onUpdated: { self.recipe = $0 }) {
                        CoverImageButtonLabel(hasImage: recipe.hasImage)
                    }
                    .padding(14)
                }

            Text(recipe.displayName)
                .font(.largeTitle.bold())
                .fontDesign(.serif)

            if let description = recipe.description?.nilIfBlank {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            FlowLayout {
                if let time = RecipeFormat.duration(recipe.prepTime) {
                    InfoChip(L("Vorb. \(time)"), systemImage: "timer")
                }
                if let time = RecipeFormat.duration(recipe.cookTime ?? recipe.performTime) {
                    InfoChip(L("Kochen \(time)"), systemImage: "flame")
                }
                if let time = RecipeFormat.duration(recipe.totalTime) {
                    InfoChip(L("Gesamt \(time)"), systemImage: "clock")
                }
                if let yield = recipe.recipeYield?.nilIfBlank, recipe.servings == nil {
                    InfoChip(yield, systemImage: "person.2")
                }
                ForEach(recipe.tags ?? []) { tag in
                    InfoChip(L("#\(tag.name)"))
                }
            }
        }
    }

    private func ingredients(_ recipe: Recipe) -> some View {
        let base = recipe.servings
        let factor = (servings ?? base).flatMap { current in base.map { current / $0 } } ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(L("Zutaten"))
                Spacer()
                if let base {
                    let current = servings ?? base
                    Stepper(value: Binding(get: { current }, set: { servings = max(0.5, $0) }),
                            in: 0.5...100, step: base >= 2 ? 1 : 0.5) {
                        Text(L("\(RecipeFormat.servings(current)) Portionen"))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(factor == 1 ? Color.secondary : Color.brand)
                    }
                    .fixedSize()
                }
            }

            if recipe.ingredients.isEmpty {
                Text(L("Keine Zutaten erkannt.")).foregroundStyle(.secondary)
            }

            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                if let title = ingredient.title?.nilIfBlank {
                    Text(title)
                        .font(.headline)
                        .padding(.top, index == 0 ? 0 : 8)
                }
                if !ingredient.isSectionHeader {
                    let checked = checkedIngredients.contains(index)
                    Button {
                        checkedIngredients.formSymmetricDifference([index])
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checked ? Color.brand : Color.secondary)
                            Text(ingredient.text(scaledBy: factor))
                                .strikethrough(checked)
                                .foregroundStyle(checked ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: checked)
                }
            }
        }
    }

    private func instructions(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(L("Zubereitung"))

            if recipe.instructions.isEmpty {
                Text(L("Keine Schritte erkannt.")).foregroundStyle(.secondary)
            }

            ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                let done = doneSteps.contains(index)
                VStack(alignment: .leading, spacing: 8) {
                    if let title = step.title?.nilIfBlank {
                        Text(title).font(.headline)
                    }
                    Button {
                        doneSteps.formSymmetricDifference([index])
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(done ? Color.secondary : Color.white)
                                .frame(width: 32, height: 32)
                                .background(done ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color.brand),
                                            in: .circle)
                            Text(step.text)
                                .font(cookMode ? .title3 : .body)
                                .foregroundStyle(done ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func notes(_ recipe: Recipe) -> some View {
        let notes = (recipe.notes ?? []).filter { $0.text?.nilIfBlank != nil }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(L("Notizen"))
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = note.title?.nilIfBlank { Text(title).font(.headline) }
                        Text(note.text ?? "")
                    }
                    .card()
                }
            }
        }
    }

    @ViewBuilder
    private func links(_ recipe: Recipe) -> some View {
        if let source = recipe.sourceURL {
            Link(destination: source) {
                Label(sourceLinkTitle(for: source), systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private func sourceLinkTitle(for url: URL) -> String {
        let kind = SourceKind(url: url)
        return kind.isVideo ? L("Video ansehen (\(kind.title))") : L("Originalrezept öffnen")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if recipe != nil {
            ToolbarItem(placement: .primaryAction) {
                Button(L("Bearbeiten"), systemImage: "pencil") { editing = true }
            }
        }
        if let keepScreenAwake {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    cookMode.toggle()
                    keepScreenAwake(cookMode)
                } label: {
                    Label(cookMode ? L("Kochmodus beenden") : L("Kochmodus"),
                          systemImage: cookMode ? "frying.pan.fill" : "frying.pan")
                }
                .tint(cookMode ? Color.brand : nil)
            }
        }
        if let webURL {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: webURL)
            }
        }
    }

    private func load() async {
        do {
            recipe = try await api.recipe(slug: slug)
            loadError = nil
        } catch {
            if recipe == nil { loadError = error.localizedDescription }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .fontDesign(.serif)
    }
}

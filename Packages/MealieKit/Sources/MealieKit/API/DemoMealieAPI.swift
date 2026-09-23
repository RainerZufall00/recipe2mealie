import Foundation

/// Offline stand-in for a Mealie server, used by SwiftUI previews and the app's demo mode.
public final class DemoMealieAPI: MealieAPI {
    public let serverURL = URL(string: "https://demo.mealie.io")!

    public init() {}

    public func currentUser() async throws -> MealieUser {
        MealieUser(id: "demo", username: "demo", fullName: "Demo-Küche", email: nil, groupSlug: "home", household: "Family")
    }

    public func recipes(page: Int, perPage: Int, search: String?, tagSlugs: [String]) async throws -> Page<RecipeSummary> {
        try await Task.sleep(for: .milliseconds(300))
        var items = Self.recipes.map(\.summary)
        if let search = search?.nilIfBlank {
            items = items.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
        }
        if !tagSlugs.isEmpty {
            items = items.filter { recipe in recipe.tags?.contains { tagSlugs.contains($0.slug) } == true }
        }
        return Page(page: 1, perPage: perPage, total: items.count, totalPages: 1, items: items)
    }

    public func recipe(slug: String) async throws -> Recipe {
        guard let recipe = Self.recipes.first(where: { $0.slug == slug }) else { throw MealieError.notFound }
        return recipe
    }

    public func deleteRecipe(slug: String) async throws {}

    public func createRecipe(name: String) async throws -> String { Self.recipes[0].slug }

    public func uploadImage(slug: String, jpeg: Data) async throws -> String { UUID().uuidString }

    public func probeRecipe(at url: URL) async throws -> String? { nil }

    public func updateRecipe(slug: String, changes: RecipePatch) async throws -> Recipe {
        var recipe = try await recipe(slug: slug)
        if let name = changes.name { recipe.name = name }
        if let description = changes.description { recipe.description = description }
        if let servings = changes.recipeServings { recipe.recipeServings = servings }
        if let time = changes.prepTime { recipe.prepTime = time }
        if let time = changes.cookTime { recipe.cookTime = time }
        if let time = changes.totalTime { recipe.totalTime = time }
        if let ingredients = changes.recipeIngredient { recipe.recipeIngredient = ingredients }
        if let steps = changes.recipeInstructions { recipe.recipeInstructions = steps }
        if let notes = changes.notes { recipe.notes = notes }
        if let tags = changes.tags { recipe.tags = tags }
        if let url = changes.orgURL { recipe.orgURL = url }
        return recipe
    }

    public func allTags() async throws -> [RecipeTag] { Self.tags }

    public func createTag(name: String) async throws -> RecipeTag {
        RecipeTag(id: UUID().uuidString, name: name, slug: name.lowercased())
    }

    public func importRecipe(from source: ImportSource, options: ImportOptions) -> AsyncThrowingStream<ImportEvent, Error> {
        let messages = source.kind.isVideo
            ? [L("Video wird heruntergeladen"), L("Audio wird mit KI transkribiert"),
               L("Rezept wird aus dem Transkript erstellt"), L("Bild wird heruntergeladen")]
            : [L("Rezeptdaten werden extrahiert"), L("Rezept wird erstellt")]
        return AsyncThrowingStream { continuation in
            let task = Task {
                for message in messages {
                    try await Task.sleep(for: .seconds(1.4))
                    continuation.yield(.progress(message))
                }
                try await Task.sleep(for: .seconds(1))
                continuation.yield(.done(slug: Self.recipes[0].slug))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Sample data

    static let tags = [
        RecipeTag(id: "t1", name: "Pasta", slug: "pasta"),
        RecipeTag(id: "t2", name: "Schnell", slug: "schnell"),
        RecipeTag(id: "t3", name: "Vegetarisch", slug: "vegetarisch"),
        RecipeTag(id: "t4", name: "Backen", slug: "backen")
    ]

    static let recipes: [Recipe] = [
        Recipe(
            recipeID: nil, slug: "one-pot-tomaten-pasta", name: "One-Pot Tomaten-Pasta",
            description: "Cremige Pasta aus einem Topf – in 20 Minuten fertig.",
            totalTime: "PT20M", prepTime: "PT5M", cookTime: "PT15M",
            recipeServings: 2, tags: [tags[0], tags[1], tags[2]],
            orgURL: "https://youtube.com/shorts/demo",
            recipeIngredient: [
                RecipeIngredient(quantity: 250, unit: IngredientUnit(name: "g"), food: IngredientFood(name: "Spaghetti"), display: "250 g Spaghetti"),
                RecipeIngredient(quantity: 400, unit: IngredientUnit(name: "g"), food: IngredientFood(name: "Kirschtomaten"), display: "400 g Kirschtomaten"),
                RecipeIngredient(quantity: 2, food: IngredientFood(name: "Knoblauchzehen"), display: "2 Knoblauchzehen"),
                RecipeIngredient(note: "etwas Olivenöl", display: "etwas Olivenöl"),
                RecipeIngredient(quantity: 50, unit: IngredientUnit(name: "g"), food: IngredientFood(name: "Parmesan"), display: "50 g Parmesan")
            ],
            recipeInstructions: [
                RecipeStep(text: "Alle Zutaten außer dem Parmesan mit 500 ml Wasser in einen breiten Topf geben."),
                RecipeStep(text: "Aufkochen und 10–12 Minuten köcheln lassen, dabei regelmäßig umrühren."),
                RecipeStep(text: "Parmesan unterheben, mit Salz und Pfeffer abschmecken und sofort servieren.")
            ],
            notes: [RecipeNote(title: L("Tipp"), text: "Mit frischem Basilikum servieren.")]
        ),
        Recipe(recipeID: nil, slug: "bananenbrot", name: "Saftiges Bananenbrot", description: "Mit sehr reifen Bananen.",
               totalTime: "PT1H10M", recipeServings: 12, tags: [tags[3]],
               recipeIngredient: [RecipeIngredient(display: "3 reife Bananen")],
               recipeInstructions: [RecipeStep(text: "Bananen zerdrücken und alles verrühren.")]),
        Recipe(recipeID: nil, slug: "shakshuka", name: "Shakshuka", description: "Eier in würziger Tomatensauce.",
               totalTime: "PT30M", recipeServings: 2, tags: [tags[2]],
               recipeIngredient: [RecipeIngredient(display: "4 Eier")],
               recipeInstructions: [RecipeStep(text: "Sauce kochen, Eier hineingleiten lassen.")])
    ]
}

extension Recipe {
    var summary: RecipeSummary {
        RecipeSummary(recipeID: recipeID, slug: slug, name: name, description: description, image: image,
                      totalTime: totalTime, prepTime: prepTime, cookTime: cookTime, performTime: performTime,
                      recipeServings: recipeServings, recipeYield: recipeYield, tags: tags,
                      recipeCategory: recipeCategory, rating: rating, orgURL: orgURL, dateAdded: nil)
    }

    init(recipeID: String?, slug: String, name: String, description: String? = nil, totalTime: String? = nil,
         prepTime: String? = nil, cookTime: String? = nil, recipeServings: Double? = nil,
         tags: [RecipeTag]? = nil, orgURL: String? = nil, recipeIngredient: [RecipeIngredient]? = nil,
         recipeInstructions: [RecipeStep]? = nil, notes: [RecipeNote]? = nil) {
        self.recipeID = recipeID
        self.slug = slug
        self.name = name
        self.description = description
        self.totalTime = totalTime
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.recipeServings = recipeServings
        self.tags = tags
        self.orgURL = orgURL
        self.recipeIngredient = recipeIngredient
        self.recipeInstructions = recipeInstructions
        self.notes = notes
    }
}

extension RecipeIngredient {
    init(quantity: Double? = nil, unit: IngredientUnit? = nil, food: IngredientFood? = nil,
         note: String? = nil, display: String) {
        self.quantity = quantity
        self.unit = unit
        self.food = food
        self.note = note
        self.display = display
    }
}

extension IngredientUnit {
    init(name: String) { self.name = name }
}

extension IngredientFood {
    init(name: String) { self.name = name }
}

extension RecipeStep {
    init(text: String) { self.text = text }
}

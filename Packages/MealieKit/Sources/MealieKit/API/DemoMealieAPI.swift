import Foundation

/// Offline stand-in for a Mealie server, used by SwiftUI previews and the app's demo mode.
///
/// The recipes are in English on purpose: the demo also serves the App Store screenshots, and
/// recipes on real servers come in whatever language their source had. The photos are from
/// Unsplash (see README → Credits).
public final class DemoMealieAPI: MealieAPI {
    public let serverURL = URL(string: "https://mealie.local")!

    public init() {}

    public func currentUser() async throws -> MealieUser {
        MealieUser(id: "demo", username: "sam", fullName: "Sam Rivera", email: nil, groupSlug: "home", household: "Family")
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

    /// Demo photos ship with the package, named after the recipe's ID.
    public func imageURL(recipeID: String, cacheKey: String?, size: RecipeImageSize) -> URL {
        Bundle.module.url(forResource: recipeID, withExtension: "jpg")
            ?? serverURL.appending(path: "api/media/recipes/\(recipeID)/images/\(size.rawValue).webp")
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

    public func allTags() async throws -> [RecipeTag] { Tags.all }

    public func createTag(name: String) async throws -> RecipeTag {
        RecipeTag(id: UUID().uuidString, name: name, slug: name.lowercased())
    }

    public func importRecipe(from source: ImportSource, options: ImportOptions) -> AsyncThrowingStream<ImportEvent, Error> {
        let messages = source.kind.isVideo
            ? [L("Video wird heruntergeladen"), L("Audio wird mit KI transkribiert"),
               L("Rezept wird aus dem Transkript erstellt"), L("Bild wird heruntergeladen")]
            : [L("Rezeptdaten werden extrahiert"), L("Rezept wird erstellt")]
        let slug = switch source {
        case .link: Self.salmon.slug
        case .text(let text): text.localizedCaseInsensitiveContains("salmon") ? Self.salmon.slug : Self.curry.slug
        case .photos: Self.bananaBread.slug
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                for message in messages {
                    try await Task.sleep(for: .seconds(1.4))
                    continuation.yield(.progress(message))
                }
                try await Task.sleep(for: .seconds(1))
                continuation.yield(.done(slug: slug))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Shared link

    /// Any link imported in the demo stands for this made-up YouTube Short, so the demo works
    /// offline and never shows someone else's video.
    static let videoURL = URL(string: "https://youtube.com/shorts/demo")!
    static let recipePageURL = URL(string: "https://weeknight-kitchen.example/recipes/crispy-salmon")!

    func preview(for url: URL) -> LinkPreview {
        let image = imageURL(recipeID: Self.salmon.recipeID ?? "", cacheKey: nil, size: .small)
        return SourceKind(url: url).isVideo
            ? LinkPreview(title: "Crispy salmon in 15 minutes 🔥 #shorts", subtitle: "Weeknight Kitchen", imageURL: image)
            : LinkPreview(title: Self.salmon.name, subtitle: url.host(), imageURL: image)
    }

    func videoInfo(for url: URL) -> YouTubeVideoInfo? {
        guard SourceKind(url: url) == .youTubeShort || SourceKind(url: url) == .youTube else { return nil }
        return YouTubeVideoInfo(
            id: "demo", title: "Crispy salmon in 15 minutes 🔥 #shorts", channel: "Weeknight Kitchen",
            description: """
                The crispiest salmon skin, every single time.

                Full recipe: \(Self.recipePageURL.absoluteString)

                Ingredients
                2 salmon fillets
                1 tbsp olive oil
                2 zucchini
                2 handfuls baby spinach
                1 lime
                """,
            durationSeconds: 58, thumbnailURL: nil)
    }

    /// What the real app would find after checking the description and the linked page.
    func findings(for url: URL) -> (findings: DescriptionFindings, recipeLinkName: String?)? {
        guard videoInfo(for: url) != nil else { return nil }
        return (DescriptionFindings(recipeLinks: [Self.recipePageURL], containsRecipe: true), Self.salmon.name)
    }

    /// Recent imports for the home screen.
    public static var importHistory: [ImportRecord] {
        let hour: TimeInterval = 3600
        let entries: [(Recipe, SourceKind, TimeInterval)] = [
            (salmon, .youTubeShort, 0.3 * hour),
            (shakshuka, .instagram, 5 * hour),
            (curry, .website, 26 * hour),
            (pancakes, .tikTok, 50 * hour),
            (bananaBread, .photos, 98 * hour)
        ]
        return entries.map { recipe, kind, age in
            ImportRecord(slug: recipe.slug, name: recipe.displayName, recipeID: recipe.recipeID,
                         imageKey: recipe.image, sourceTitle: kind.title, sourceURL: nil,
                         date: .now.addingTimeInterval(-age))
        }
    }

    // MARK: Sample data

    enum Tags {
        static let breakfast = tag("Breakfast")
        static let dinner = tag("Dinner")
        static let quick = tag("Quick")
        static let vegetarian = tag("Vegetarian")
        static let vegan = tag("Vegan")
        static let fish = tag("Fish")
        static let pasta = tag("Pasta")
        static let spicy = tag("Spicy")
        static let baking = tag("Baking")

        static let all = [breakfast, dinner, quick, vegetarian, vegan, fish, pasta, spicy, baking]

        private static func tag(_ name: String) -> RecipeTag {
            RecipeTag(id: name.lowercased(), name: name, slug: name.lowercased())
        }
    }

    static let salmon = Recipe(
        slug: "crispy-salmon-zucchini-noodles", name: "Crispy Salmon with Zucchini Noodles",
        description: "Crackling skin, tender inside and a pan of garlicky greens – ready in 20 minutes.",
        totalTime: "PT20M", prepTime: "PT10M", cookTime: "PT10M", recipeServings: 2,
        tags: [Tags.fish, Tags.quick, Tags.dinner], orgURL: videoURL.absoluteString,
        recipeIngredient: [
            .amount(2, nil, "salmon fillets, skin on"),
            .amount(1, "tbsp", "olive oil"),
            .amount(2, nil, "zucchini, spiralized"),
            .amount(1, nil, "carrot, cut into thin strips"),
            .amount(2, "handfuls", "baby spinach"),
            .amount(1, nil, "garlic clove, grated"),
            .amount(1, nil, "lime"),
            .text("Salt and pepper")
        ],
        recipeInstructions: [
            "Pat the salmon dry and season the skin generously with salt.",
            "Heat the oil in a pan over medium-high heat. Lay the fillets in skin side down and press them flat for 10 seconds. Cook for 5–6 minutes until the skin is crisp.",
            "Flip and cook for 1–2 minutes more, then let the fish rest.",
            "In the same pan, toss the zucchini, carrot and garlic for 2 minutes. Add the spinach and let it wilt.",
            "Season with lime juice, salt and pepper and serve the salmon on top with lime wedges."
        ],
        notes: [RecipeNote(title: "Tip", text: "Don't move the fillets while the skin crisps – they let go of the pan on their own when they're ready.")]
    )

    static let shakshuka = Recipe(
        slug: "shakshuka", name: "Shakshuka",
        description: "Eggs gently poached in a smoky, spiced tomato and pepper sauce.",
        totalTime: "PT30M", prepTime: "PT10M", cookTime: "PT20M", recipeServings: 2,
        tags: [Tags.breakfast, Tags.vegetarian], orgURL: "https://instagram.com/reel/demo",
        recipeIngredient: [
            .amount(2, "tbsp", "olive oil"),
            .amount(1, nil, "onion, finely chopped"),
            .amount(1, nil, "red bell pepper, diced"),
            .amount(2, nil, "garlic cloves, sliced"),
            .amount(1, "tsp", "ground cumin"),
            .amount(1, "tsp", "sweet paprika"),
            .amount(0.25, "tsp", "chili flakes"),
            .amount(400, "g", "canned chopped tomatoes"),
            .amount(4, nil, "eggs"),
            .text("A small bunch of parsley, chopped"),
            .text("Crusty bread, to serve")
        ],
        recipeInstructions: [
            "Heat the oil in a large pan and soften the onion and pepper for 6–8 minutes.",
            "Stir in the garlic and spices and cook for 1 minute until fragrant.",
            "Add the tomatoes, season with salt and simmer for 10 minutes until thick.",
            "Make four wells in the sauce and crack an egg into each. Cover and cook for 5–7 minutes until the whites are set.",
            "Scatter with parsley and serve straight from the pan with bread."
        ]
    )

    static let curry = Recipe(
        slug: "thai-red-curry-tofu", name: "Thai Red Curry with Tofu",
        description: "Creamy coconut curry with crispy tofu, eggplant and bok choy.",
        totalTime: "PT35M", prepTime: "PT15M", cookTime: "PT20M", recipeServings: 4,
        tags: [Tags.vegan, Tags.spicy, Tags.dinner], orgURL: "https://weeknight-kitchen.example/recipes/red-curry",
        recipeIngredient: [
            .amount(400, "g", "firm tofu, cubed"),
            .amount(1, "tbsp", "coconut oil"),
            .amount(3, "tbsp", "red curry paste"),
            .amount(400, "ml", "coconut milk"),
            .amount(200, "ml", "vegetable stock"),
            .amount(1, nil, "small eggplant, cut into chunks"),
            .amount(2, nil, "heads bok choy, halved"),
            .amount(1, "tbsp", "soy sauce"),
            .amount(1, nil, "lime"),
            .amount(1, nil, "red chili, sliced"),
            .text("Thai basil and jasmine rice, to serve")
        ],
        recipeInstructions: [
            "Press the tofu dry and fry it in the oil until golden on all sides. Set aside.",
            "Fry the curry paste in the same pot for 1 minute, then stir in the coconut milk and stock.",
            "Add the eggplant and simmer for 10 minutes until tender.",
            "Add the bok choy and tofu and cook for 3 more minutes.",
            "Season with soy sauce and lime juice. Top with chili and Thai basil and serve with rice."
        ],
        notes: [RecipeNote(title: "Tip", text: "Check the curry paste: some brands contain shrimp paste.")]
    )

    static let pasta = Recipe(
        slug: "one-pot-tomato-pasta", name: "One-Pot Tomato Pasta",
        description: "Everything cooks in one pot – the pasta starch makes the sauce silky.",
        totalTime: "PT20M", prepTime: "PT5M", cookTime: "PT15M", recipeServings: 2,
        tags: [Tags.pasta, Tags.quick, Tags.vegetarian],
        recipeIngredient: [
            .amount(250, "g", "fusilli"),
            .amount(300, "g", "cherry tomatoes, halved"),
            .amount(1, nil, "small red onion, finely chopped"),
            .amount(2, nil, "garlic cloves, sliced"),
            .amount(2, "tbsp", "tomato paste"),
            .amount(2, "tbsp", "olive oil"),
            .amount(600, "ml", "water"),
            .amount(40, "g", "parmesan, grated"),
            .text("Fresh basil, to serve")
        ],
        recipeInstructions: [
            "Put everything except the parmesan and basil into a wide pot with the water and a good pinch of salt.",
            "Bring to a boil and simmer for 10–12 minutes, stirring often, until the pasta is al dente and the sauce is glossy.",
            "Stir in the parmesan, season with pepper and top with basil."
        ],
        notes: [RecipeNote(title: "Tip", text: "Add a splash of water if the sauce gets too thick before the pasta is done.")]
    )

    static let tacos = Recipe(
        slug: "carnitas-tacos", name: "Carnitas Tacos",
        description: "Slow-braised pork with orange and cumin, crisped up under the grill.",
        totalTime: "PT3H20M", prepTime: "PT20M", cookTime: "PT3H", recipeServings: 4,
        tags: [Tags.dinner],
        recipeIngredient: [
            .amount(1, "kg", "pork shoulder, in large chunks"),
            .amount(2, "tsp", "ground cumin"),
            .amount(1, "tsp", "dried oregano"),
            .amount(1, "tsp", "salt"),
            .amount(1, nil, "onion, quartered"),
            .amount(4, nil, "garlic cloves"),
            .amount(1, nil, "orange"),
            .amount(8, nil, "small corn tortillas"),
            .amount(1, nil, "small red onion, finely diced"),
            .amount(2, nil, "limes, cut into wedges"),
            .text("Cilantro, to serve")
        ],
        recipeInstructions: [
            "Rub the pork with cumin, oregano and salt. Put it in a heavy pot with the onion, garlic, the orange juice and the squeezed orange halves.",
            "Add water until the meat is half covered. Cover and braise at 160 °C (320 °F) for 2½–3 hours until it falls apart.",
            "Shred the meat with two forks, spread it on a baking tray and grill for 5 minutes until the edges are crisp.",
            "Warm the tortillas in a dry pan and fill them with the carnitas, red onion and cilantro. Serve with lime wedges."
        ]
    )

    static let bowl = Recipe(
        slug: "rainbow-buddha-bowl", name: "Rainbow Buddha Bowl",
        description: "Quinoa, roasted chickpeas and crunchy vegetables with a lemon tahini dressing.",
        totalTime: "PT30M", prepTime: "PT15M", cookTime: "PT15M", recipeServings: 2,
        tags: [Tags.vegan, Tags.quick],
        recipeIngredient: [
            .section("Bowl"),
            .amount(150, "g", "quinoa"),
            .amount(400, "g", "canned chickpeas, drained"),
            .amount(1, "tsp", "smoked paprika"),
            .amount(150, "g", "cherry tomatoes, halved"),
            .amount(0.25, nil, "red cabbage, finely shredded"),
            .amount(1, nil, "yellow bell pepper, sliced"),
            .amount(100, "g", "green beans, blanched"),
            .amount(1, nil, "avocado, sliced"),
            .amount(2, "tbsp", "walnuts"),
            .section("Lemon tahini dressing"),
            .amount(3, "tbsp", "tahini"),
            .amount(1, nil, "lemon, juiced"),
            .amount(1, "tsp", "maple syrup"),
            .amount(3, "tbsp", "water")
        ],
        recipeInstructions: [
            "Cook the quinoa according to the packet instructions.",
            "Toss the chickpeas with paprika, salt and a little oil and roast at 200 °C (400 °F) for 15 minutes.",
            "Whisk the tahini with the lemon juice, maple syrup, water and a pinch of salt until smooth.",
            "Divide the quinoa between two bowls, arrange the vegetables, avocado and chickpeas on top, sprinkle with walnuts and drizzle with the dressing."
        ]
    )

    static let pancakes = Recipe(
        slug: "blueberry-pancakes", name: "Fluffy Blueberry Pancakes",
        description: "Thick buttermilk pancakes with juicy blueberries and maple syrup.",
        totalTime: "PT25M", prepTime: "PT10M", cookTime: "PT15M", recipeServings: 4,
        tags: [Tags.breakfast, Tags.vegetarian], orgURL: "https://tiktok.com/@demo/video/1",
        recipeIngredient: [
            .amount(200, "g", "flour"),
            .amount(2, "tbsp", "sugar"),
            .amount(2, "tsp", "baking powder"),
            .amount(0.25, "tsp", "salt"),
            .amount(250, "ml", "buttermilk"),
            .amount(2, nil, "eggs"),
            .amount(30, "g", "butter, melted"),
            .amount(150, "g", "blueberries"),
            .text("Maple syrup, to serve")
        ],
        recipeInstructions: [
            "Whisk the flour, sugar, baking powder and salt in a bowl.",
            "In a second bowl, whisk the buttermilk, eggs and melted butter. Pour into the dry ingredients and stir until just combined – a few lumps are fine.",
            "Heat a lightly buttered pan over medium heat. Add 3 tablespoons of batter per pancake and scatter a few blueberries on top.",
            "Flip when bubbles appear on the surface, after about 2 minutes, and cook for 1 more minute.",
            "Stack them up, top with the remaining blueberries and pour over maple syrup."
        ]
    )

    static let bananaBread = Recipe(
        slug: "banana-bread", name: "Banana Bread",
        description: "Moist, not too sweet and the best use for very ripe bananas.",
        totalTime: "PT1H10M", prepTime: "PT15M", cookTime: "PT55M", recipeServings: 10,
        tags: [Tags.baking, Tags.breakfast],
        recipeIngredient: [
            .amount(4, nil, "very ripe bananas (1 for the top)"),
            .amount(80, "g", "butter, melted"),
            .amount(100, "g", "brown sugar"),
            .amount(1, nil, "egg"),
            .amount(1, "tsp", "vanilla extract"),
            .amount(1, "tsp", "baking soda"),
            .amount(0.5, "tsp", "cinnamon"),
            .amount(190, "g", "flour"),
            .amount(50, "g", "walnuts, chopped"),
            .text("A pinch of salt")
        ],
        recipeInstructions: [
            "Heat the oven to 175 °C (350 °F) and line a loaf pan with baking paper.",
            "Mash 3 bananas with a fork, then stir in the butter, sugar, egg and vanilla.",
            "Mix in the baking soda, cinnamon, salt and flour until just combined, then fold in the walnuts.",
            "Pour into the pan, top with slices of the last banana and bake for 50–60 minutes, until a skewer comes out clean.",
            "Let it cool in the pan for 10 minutes before slicing."
        ],
        notes: [RecipeNote(title: "Tip", text: "The browner the bananas, the sweeter and moister the bread.")]
    )

    /// Newest first, like Mealie's default sort.
    static let recipes: [Recipe] = [salmon, shakshuka, curry, pasta, tacos, bowl, pancakes, bananaBread]
}

extension Recipe {
    var summary: RecipeSummary {
        RecipeSummary(recipeID: recipeID, slug: slug, name: name, description: description, image: image,
                      totalTime: totalTime, prepTime: prepTime, cookTime: cookTime, performTime: performTime,
                      recipeServings: recipeServings, recipeYield: recipeYield, tags: tags,
                      recipeCategory: recipeCategory, rating: rating, orgURL: orgURL, dateAdded: nil)
    }

    /// A demo recipe. Its photo is `Resources/DemoImages/<slug>.jpg`, when there is one.
    init(slug: String, name: String, description: String? = nil, totalTime: String? = nil,
         prepTime: String? = nil, cookTime: String? = nil, recipeServings: Double? = nil,
         tags: [RecipeTag]? = nil, orgURL: String? = nil, recipeIngredient: [RecipeIngredient]? = nil,
         recipeInstructions: [String]? = nil, notes: [RecipeNote]? = nil) {
        let hasPhoto = Bundle.module.url(forResource: slug, withExtension: "jpg") != nil
        self.recipeID = slug
        self.image = hasPhoto ? "demo" : nil
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
        self.recipeInstructions = recipeInstructions?.map { RecipeStep(text: $0) }
        self.notes = notes
    }
}

extension RecipeIngredient {
    /// "2 tbsp olive oil", with quantity, unit and food filled in so servings can be scaled.
    static func amount(_ quantity: Double, _ unit: String?, _ food: String) -> RecipeIngredient {
        RecipeIngredient(quantity: quantity, unit: unit.map(IngredientUnit.init(name:)),
                         food: IngredientFood(name: food),
                         display: [RecipeFormat.quantity(quantity), unit, food].compactMap { $0 }.joined(separator: " "))
    }

    /// An ingredient without an amount, like "Salt and pepper".
    static func text(_ text: String) -> RecipeIngredient {
        RecipeIngredient(note: text, display: text)
    }

    /// A heading such as "For the dressing".
    static func section(_ title: String) -> RecipeIngredient {
        RecipeIngredient(title: title, display: "")
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

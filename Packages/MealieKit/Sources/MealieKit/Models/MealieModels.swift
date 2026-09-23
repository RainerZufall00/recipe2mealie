import Foundation

// DTOs for the Mealie REST API (v3.x). Fields are optional wherever Mealie may omit them,
// so newer or older servers don't break decoding.

public struct RecipeSummary: Codable, Hashable, Identifiable, Sendable {
    /// Mealie's UUID, needed for image URLs. Identity is the slug, which is always present.
    public var recipeID: String?
    public var slug: String
    public var name: String?
    public var description: String?
    public var image: String?
    public var totalTime: String?
    public var prepTime: String?
    public var cookTime: String?
    public var performTime: String?
    public var recipeServings: Double?
    public var recipeYield: String?
    public var tags: [RecipeTag]?
    public var recipeCategory: [RecipeCategory]?
    public var rating: Double?
    public var orgURL: String?
    public var dateAdded: String?

    public var id: String { slug }
    public var displayName: String { name?.nilIfBlank ?? slug }
    public var hasImage: Bool { image != nil && recipeID != nil }

    enum CodingKeys: String, CodingKey {
        case recipeID = "id"
        case slug, name, description, image, totalTime, prepTime, cookTime, performTime
        case recipeServings, recipeYield, tags, recipeCategory, rating, orgURL, dateAdded
    }
}

public struct Recipe: Codable, Hashable, Identifiable, Sendable {
    public var recipeID: String?
    public var slug: String
    public var name: String?
    public var description: String?
    public var image: String?
    public var totalTime: String?
    public var prepTime: String?
    public var cookTime: String?
    public var performTime: String?
    public var recipeServings: Double?
    public var recipeYieldQuantity: Double?
    public var recipeYield: String?
    public var tags: [RecipeTag]?
    public var recipeCategory: [RecipeCategory]?
    public var rating: Double?
    public var orgURL: String?
    public var recipeIngredient: [RecipeIngredient]?
    public var recipeInstructions: [RecipeStep]?
    public var notes: [RecipeNote]?

    public var id: String { slug }
    public var displayName: String { name?.nilIfBlank ?? slug }
    public var ingredients: [RecipeIngredient] { recipeIngredient ?? [] }
    public var instructions: [RecipeStep] { recipeInstructions ?? [] }
    public var hasImage: Bool { image != nil && recipeID != nil }
    public var sourceURL: URL? { orgURL.flatMap { URL(string: $0) } }

    enum CodingKeys: String, CodingKey {
        case recipeID = "id"
        case slug, name, description, image, totalTime, prepTime, cookTime, performTime
        case recipeServings, recipeYieldQuantity, recipeYield, tags, recipeCategory, rating, orgURL
        case recipeIngredient, recipeInstructions, notes
    }

    /// Servings as a number, falling back to Mealie's yield quantity.
    public var servings: Double? {
        if let recipeServings, recipeServings > 0 { return recipeServings }
        if let recipeYieldQuantity, recipeYieldQuantity > 0 { return recipeYieldQuantity }
        return nil
    }
}

public struct RecipeTag: Codable, Hashable, Identifiable, Sendable {
    public var id: String?
    public var name: String
    public var slug: String

    public init(id: String?, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct RecipeCategory: Codable, Hashable, Identifiable, Sendable {
    public var id: String?
    public var name: String
    public var slug: String
}

public struct RecipeIngredient: Codable, Hashable, Sendable {
    public var referenceId: String?
    public var title: String?
    public var quantity: Double?
    public var unit: IngredientUnit?
    public var food: IngredientFood?
    public var note: String?
    public var display: String?
    public var originalText: String?

    public init(referenceId: String? = nil, title: String? = nil, quantity: Double? = nil,
                unit: IngredientUnit? = nil, food: IngredientFood? = nil, note: String? = nil,
                display: String? = nil, originalText: String? = nil) {
        self.referenceId = referenceId
        self.title = title
        self.quantity = quantity
        self.unit = unit
        self.food = food
        self.note = note
        self.display = display
        self.originalText = originalText
    }

    /// An ingredient the user typed. Mealie builds `display` from `note` when it is empty.
    public static func freeText(_ text: String, title: String? = nil) -> RecipeIngredient {
        RecipeIngredient(title: title, note: text, display: "", originalText: text)
    }

    /// `quantity` is written even when nil: leaving it out makes Mealie fall back to 0,
    /// which would show "0" in front of ingredients that never had an amount.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(referenceId, forKey: .referenceId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(unit, forKey: .unit)
        try container.encodeIfPresent(food, forKey: .food)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(display, forKey: .display)
        try container.encodeIfPresent(originalText, forKey: .originalText)
    }
}

/// Fields to change on an existing recipe. Everything left nil stays untouched.
public struct RecipePatch: Encodable, Sendable {
    public var name: String?
    public var description: String?
    public var recipeServings: Double?
    public var prepTime: String?
    public var cookTime: String?
    public var totalTime: String?
    public var recipeIngredient: [RecipeIngredient]?
    public var recipeInstructions: [RecipeStep]?
    public var notes: [RecipeNote]?
    public var tags: [RecipeTag]?
    public var orgURL: String?

    public init(name: String? = nil, description: String? = nil, recipeServings: Double? = nil,
                prepTime: String? = nil, cookTime: String? = nil, totalTime: String? = nil,
                recipeIngredient: [RecipeIngredient]? = nil, recipeInstructions: [RecipeStep]? = nil,
                notes: [RecipeNote]? = nil, tags: [RecipeTag]? = nil, orgURL: String? = nil) {
        self.name = name
        self.description = description
        self.recipeServings = recipeServings
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.totalTime = totalTime
        self.recipeIngredient = recipeIngredient
        self.recipeInstructions = recipeInstructions
        self.notes = notes
        self.tags = tags
        self.orgURL = orgURL
    }
}

public struct IngredientUnit: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String
    public var pluralName: String?
    public var abbreviation: String?
    public var useAbbreviation: Bool?
    public var fraction: Bool?
}

public struct IngredientFood: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String
    public var pluralName: String?
}

public struct RecipeStep: Codable, Hashable, Sendable {
    public var id: String?
    public var title: String?
    public var summary: String?
    public var text: String
}

public struct RecipeNote: Codable, Hashable, Sendable {
    public var title: String?
    public var text: String?
}

/// Mealie's pagination envelope. It uses snake_case (`per_page`) unlike the rest of the API,
/// and older versions differ, so both spellings are accepted and counts are optional.
public struct Page<Item: Codable & Sendable>: Codable, Sendable {
    public var page: Int
    public var perPage: Int
    public var total: Int
    public var totalPages: Int
    public var items: [Item]

    public var hasMore: Bool { page < totalPages }

    enum CodingKeys: String, CodingKey {
        case page, total, items
        case perPage, per_page
        case totalPages, total_pages
    }

    public init(page: Int, perPage: Int, total: Int, totalPages: Int, items: [Item]) {
        self.page = page
        self.perPage = perPage
        self.total = total
        self.totalPages = totalPages
        self.items = items
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        perPage = try container.decodeIfPresent(Int.self, forKey: .perPage)
            ?? container.decodeIfPresent(Int.self, forKey: .per_page)
            ?? items.count
        totalPages = try container.decodeIfPresent(Int.self, forKey: .totalPages)
            ?? container.decodeIfPresent(Int.self, forKey: .total_pages)
            ?? 1
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(page, forKey: .page)
        try container.encode(perPage, forKey: .perPage)
        try container.encode(total, forKey: .total)
        try container.encode(totalPages, forKey: .totalPages)
        try container.encode(items, forKey: .items)
    }
}

public struct MealieUser: Codable, Hashable, Sendable {
    public var id: String?
    public var username: String?
    public var fullName: String?
    public var email: String?
    public var groupSlug: String?
    public var household: String?

    public var displayName: String { fullName?.nilIfBlank ?? username ?? email ?? "Mealie" }
}

public struct MealieAppInfo: Codable, Sendable {
    public var version: String
    public var allowPasswordLogin: Bool?
}

struct AuthTokenResponse: Codable {
    var accessToken: String

    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

struct APITokenResponse: Codable {
    var token: String
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

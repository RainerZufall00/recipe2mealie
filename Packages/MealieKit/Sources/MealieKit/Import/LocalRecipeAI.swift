import FoundationModels
import Foundation
import UIKit
import Vision

/// Turns photos and pasted text into a recipe **on the device**, using Vision for text
/// recognition and Apple's on-device language model for the structure. Nothing leaves the phone
/// until the finished recipe is saved to Mealie.
public enum LocalRecipeAI {
    public enum Availability: Equatable, Sendable {
        case available
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case unsupportedLanguage

        public var isAvailable: Bool { self == .available }

        /// What to tell the user when local processing can't run.
        public var message: String? {
            switch self {
            case .available: nil
            case .deviceNotEligible: L("Dieses Gerät unterstützt Apple Intelligence nicht.")
            case .notEnabled: L("Apple Intelligence ist ausgeschaltet. Du kannst es in den Systemeinstellungen aktivieren.")
            case .modelNotReady: L("Das lokale Modell wird noch geladen. Versuch es gleich noch einmal.")
            case .unsupportedLanguage: L("Die lokale Verarbeitung unterstützt diese Sprache nicht.")
            }
        }
    }

    public static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            .notEnabled
        case .unavailable(.modelNotReady):
            .modelNotReady
        case .unavailable:
            .modelNotReady
        }
    }

    /// Warms the model up while the user is still looking at the preview.
    public static func prewarm() {
        guard availability.isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }

    // MARK: Text recognition

    /// Reads the text of a photo with Vision. Runs fully on device and needs no AI model.
    public static func recognizeText(in imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { return "" }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US")]

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: Extraction

    /// The recipe as the model is allowed to report it: text copied from the source, never invented.
    @Generable
    struct Extraction {
        @Guide(description: "The recipe title exactly as written in the source.")
        var title: String

        @Guide(description: "One short sentence describing the dish, only if the source has one. Otherwise empty.")
        var summary: String

        @Guide(description: "Servings exactly as stated, e.g. '4 Portionen'. Empty if the source does not say.")
        var servings: String

        @Guide(description: "Total time exactly as stated, e.g. '30 Minuten'. Empty if the source does not say.")
        var totalTime: String

        @Guide(description: "Every ingredient line, copied word for word including amounts as written.",
               .maximumCount(60))
        var ingredients: [String]

        @Guide(description: "The preparation steps in order, each one sentence or more, as written in the source.",
               .maximumCount(40))
        var steps: [String]
    }

    static let instructions = """
        You extract a recipe from text that was copied or scanned from a photo, a website or a \
        message. The text may be messy, with line breaks in odd places.

        Rules you must follow:
        - Copy what the source says. Never invent amounts, units, ingredients or steps.
        - If an amount is missing, keep the ingredient text as it is ("etwas Olivenöl" stays \
          "etwas Olivenöl"). Do not add a number.
        - Leave a field empty when the source does not contain that information.
        - Keep the language of the source. Do not translate.
        - Merge lines that clearly belong to one ingredient or one step.
        - Ignore page numbers, prices, navigation text, comments and advertising.
        """

    /// Builds a recipe from the collected text. Throws when the model is unavailable or refuses.
    public static func extract(from text: String) async throws -> Recipe {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 30 else { throw LocalAIError.notEnoughText }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Extract the recipe from this source text:\n\n\(clip(trimmed))"

        do {
            let response = try await session.respond(to: prompt,
                                                     generating: Extraction.self,
                                                     options: greedyOptions)
            return recipe(from: response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw LocalAIError.generation(error)
        } catch {
            // Anything else (model not installed, inference unavailable on this machine, …).
            log.error("On-device extraction failed: \(error)")
            throw LocalAIError.unavailable
        }
    }

    // MARK: Cover image

    @Generable
    struct DishName {
        @Guide(description: "The plain name of the dish in one to four words, e.g. 'Kartoffelsuppe' or 'Käsespätzle'. No adjectives like 'best', 'easy' or 'creamy', no numbers, no emojis, no clickbait. Same language as the title.")
        var dish: String
    }

    /// Strips a video-style title ("Die leckerste Kartoffelsuppe 🔥") down to the dish itself,
    /// which is what Image Playground should draw.
    public static func dishName(from title: String) async throws -> String {
        let session = LanguageModelSession(
            instructions: "You turn recipe titles into the plain name of the dish. Use only words from the title.")
        let result = try await session.respond(to: "Title: \(title)",
                                               generating: DishName.self,
                                               options: greedyOptions).content
        return result.dish.nilIfBlank ?? title
    }

    /// Deterministic output. The initializer was renamed in the iOS 27 SDK (Xcode 27, Swift 6.4);
    /// the check keeps the project building with Xcode 26 too.
    private static var greedyOptions: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    /// Keeps the prompt inside the on-device context window; a recipe rarely needs more.
    private static func clip(_ text: String, limit: Int = 6000) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }

    static func recipe(from extraction: Extraction) -> Recipe {
        var recipe = Recipe(recipeID: nil, slug: "", name: extraction.title.nilIfBlank ?? L("Neues Rezept"))
        recipe.description = extraction.summary.nilIfBlank
        recipe.totalTime = extraction.totalTime.nilIfBlank
        recipe.recipeYield = extraction.servings.nilIfBlank
        recipe.recipeServings = servingsNumber(from: extraction.servings)
        recipe.recipeIngredient = extraction.ingredients
            .compactMap { $0.nilIfBlank }
            .map { RecipeIngredient.freeText($0) }
        recipe.recipeInstructions = extraction.steps
            .compactMap { $0.nilIfBlank }
            .map { RecipeStep(id: nil, title: nil, summary: nil, text: $0) }
        return recipe
    }

    /// Pulls the leading number out of "4 Portionen" without guessing when there is none.
    static func servingsNumber(from text: String) -> Double? {
        let digits = text.prefix { $0.isNumber || $0 == "," || $0 == "." }
            .replacingOccurrences(of: ",", with: ".")
        return Double(digits)
    }
}

public enum LocalAIError: LocalizedError {
    case notEnoughText
    case unavailable
    case generation(LanguageModelSession.GenerationError)

    public var errorDescription: String? {
        switch self {
        case .notEnoughText:
            L("In der Quelle steht zu wenig Text für ein Rezept.")
        case .unavailable:
            L("Das lokale Modell konnte nicht antworten. Auf dem Simulator steht Apple Intelligence oft nicht bereit.")
        case .generation(let error):
            switch error {
            case .exceededContextWindowSize:
                L("Die Quelle ist zu lang für die lokale Verarbeitung.")
            case .guardrailViolation:
                L("Das lokale Modell hat die Verarbeitung abgelehnt.")
            case .unsupportedLanguageOrLocale:
                L("Die lokale Verarbeitung unterstützt diese Sprache nicht.")
            default:
                L("Die lokale Verarbeitung ist fehlgeschlagen.")
            }
        }
    }
}

import Foundation

/// What a video description offers besides the video itself.
public struct DescriptionFindings: Sendable, Equatable {
    /// Links that most likely lead to the written recipe, best first.
    public var recipeLinks: [URL]
    /// The description itself looks like it contains ingredients and steps.
    public var containsRecipe: Bool

    public var isEmpty: Bool { recipeLinks.isEmpty && !containsRecipe }
}

/// Plain heuristics, no AI: fast, free and predictable. Tuned for cooking videos, where the
/// description often has the full recipe or a link to the creator's blog.
public enum DescriptionAnalyzer {
    public static func analyze(_ description: String) -> DescriptionFindings {
        let lines = description.components(separatedBy: .newlines)
        return DescriptionFindings(recipeLinks: recipeLinks(in: lines), containsRecipe: looksLikeRecipe(lines))
    }

    // MARK: Links

    private static let recipeWords = ["rezept", "recipe", "zutaten", "ingredients", "anleitung",
                                      "printable", "zum nachkochen", "nachlesen"]

    /// Social networks, shops, affiliate and payment links never hold the recipe.
    private static let ignoredHosts = ["youtube.com", "youtu.be", "instagram.com", "tiktok.com", "facebook.com",
                                       "fb.com", "twitter.com", "x.com", "threads.net", "pinterest.",
                                       "amazon.", "amzn.", "patreon.com", "paypal.", "spotify.com",
                                       "apple.com", "discord.", "t.me", "whatsapp.", "linktr.ee",
                                       "snapchat.com", "twitch.tv", "steadyhq.com", "ko-fi.com"]

    static func recipeLinks(in lines: [String]) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var ranked: [(url: URL, score: Int)] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            for match in detector.matches(in: line, range: range) {
                guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host()?.lowercased(),
                      !ignoredHosts.contains(where: { host.contains($0) }) else { continue }

                // The link is only a candidate when the line around it, the line before it
                // ("Zum Rezept:" ↵ link) or the URL itself talks about the recipe.
                let context = (index > 0 ? lines[index - 1] + " " : "") + line
                let path = url.path().lowercased()
                var score = 0
                if recipeWords.contains(where: { context.lowercased().contains($0) }) { score += 2 }
                if path.contains("rezept") || path.contains("recipe") { score += 2 }
                guard score > 0, !ranked.contains(where: { $0.url == url }) else { continue }
                ranked.append((url, score))
            }
        }
        return ranked.sorted { $0.score > $1.score }.map(\.url)
    }

    // MARK: Recipe text

    private static let headings = ["zutaten", "ingredients", "zubereitung", "anleitung", "instructions",
                                   "method", "für den teig", "für die sauce", "für die soße"]

    private static let units = ["g", "kg", "mg", "ml", "l", "cl", "dl", "el", "tl", "msp", "tbsp", "tsp",
                                "cup", "cups", "oz", "lb", "lbs", "prise", "prisen", "stk", "stück", "zehe",
                                "zehen", "dose", "dosen", "bund", "scheibe", "scheiben", "pck", "päckchen",
                                "becher", "glas", "handvoll", "tasse", "tassen", "zweig", "zweige"]

    static func looksLikeRecipe(_ lines: [String]) -> Bool {
        let hasHeading = lines.contains { line in
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            return headings.contains { lower.hasPrefix($0) || lower.hasPrefix("• \($0)") || lower.hasPrefix("- \($0)") }
        }
        let ingredientLines = lines.filter(isIngredientLine).count
        return (hasHeading && ingredientLines >= 2) || ingredientLines >= 4
    }

    /// "200 g Mehl", "- 2 EL Olivenöl", "½ TL Salz", but not "0:00 Intro" or "20 % Rabatt".
    static func isIngredientLine(_ line: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces).lowercased()
        while let first = text.first, "-•*·–▪︎✔️✅🔸🔹".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard let first = text.first, first.isNumber || "½¼¾⅓⅔".contains(first) else { return false }
        if text.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return false } // timestamp
        if text.contains("%") || text.contains("€") || text.contains("$") || text.contains("http") { return false }

        // Amount, optional unit, then a word: "200 g mehl", "3 eier", "1/2 tl salz".
        let words = text.replacingOccurrences(of: #"^[\d.,/½¼¾⅓⅔\s-]+"#, with: "", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        guard let firstWord = words.first else { return false }
        if units.contains(firstWord.trimmingCharacters(in: .punctuationCharacters)) { return words.count >= 2 }
        return firstWord.first?.isLetter == true && text.count < 80
    }
}

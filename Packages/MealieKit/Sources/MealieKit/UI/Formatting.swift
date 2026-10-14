import Foundation

public enum RecipeFormat {
    /// Mealie stores times as free text ("25 Minuten", "3 hours") or ISO 8601 ("PT1H30M").
    public static func duration(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else { return nil }
        guard raw.uppercased().hasPrefix("PT") || raw.uppercased().hasPrefix("P") else {
            return spelledOutDuration(raw) ?? raw
        }
        var hours = 0.0, minutes = 0.0, number = ""
        for character in raw.uppercased().dropFirst() {
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            let value = Double(number) ?? 0
            number = ""
            switch character {
            case "D": hours += value * 24
            case "H": hours += value
            case "M": minutes += value
            case "S": minutes += value / 60
            default: continue
            }
        }
        let total = Int((hours * 60 + minutes).rounded())
        guard total > 0 else { return raw }
        let components = DateComponents(minute: total)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = total >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: components) ?? raw
    }

    /// Turns "3 hours", "1 hr 30 min" or "25 Minuten" into a duration in the user's language.
    /// Returns nil when the text is anything else, so it is shown unchanged.
    private static func spelledOutDuration(_ raw: String) -> String? {
        let units: [(names: [String], minutes: Int)] = [
            (["tag", "tage", "day", "days", "d"], 1440),
            (["stunde", "stunden", "std", "hour", "hours", "hrs", "hr", "h"], 60),
            (["minute", "minuten", "min", "mins", "minutes", "m"], 1)
        ]
        let tokens = raw.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        var total = 0
        var pendingValue: Int?
        for token in tokens {
            if let number = Int(token) {
                if pendingValue != nil { return nil } // two numbers in a row: not a duration
                pendingValue = number
                continue
            }
            guard let value = pendingValue,
                  let unit = units.first(where: { $0.names.contains(token) }) else { return nil }
            total += value * unit.minutes
            pendingValue = nil
        }
        guard pendingValue == nil, total > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = total >= 1440 ? [.day, .hour, .minute] : (total >= 60 ? [.hour, .minute] : [.minute])
        formatter.unitsStyle = .short
        return formatter.string(from: DateComponents(minute: total))
    }

    public static func quantity(_ value: Double) -> String {
        // "333,33 g" after scaling is no help in the kitchen.
        if value >= 10 { return String(Int(value.rounded())) }
        let whole = value.rounded(.down)
        let fraction = value - whole
        let fractions: [(Double, String)] = [(0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾")]
        if fraction < 0.01 { return String(Int(whole)) }
        if let match = fractions.first(where: { abs($0.0 - fraction) < 0.02 }) {
            return whole == 0 ? match.1 : "\(Int(whole))\(match.1)"
        }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    public static func servings(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The amount a free-text ingredient line starts with, like "4", "1/2", "1 ½", "1,5" or "2–3".
    struct LeadingAmount {
        /// One value, or two for a range.
        var values: [Double]
        var range: Range<String.Index>
    }

    static func leadingAmount(in text: String) -> LeadingAmount? {
        let number = #"\d+[.,]\d+|\d+\s+\d+/\d+|\d+\s?[¼½¾⅓⅔⅛]|\d+/\d+|[¼½¾⅓⅔⅛]|\d+"#
        // An optional list bullet, then a number or a range of two.
        let pattern = #"^\s*(?:[-•*]\s+)?(?<first>"# + number + #")(?:\s*[-–]\s*(?<second>"# + number + #"))?"#
        guard let regex = try? Regex(pattern),
              let match = try? regex.prefixMatch(in: text),
              let first = match["first"]?.substring, let start = match["first"]?.range?.lowerBound,
              let firstValue = amount(from: first) else { return nil }
        var values = [firstValue]
        var end = first.endIndex
        if let second = match["second"]?.substring, let secondValue = amount(from: second) {
            values.append(secondValue)
            end = second.endIndex
        }
        return LeadingAmount(values: values, range: start..<end)
    }

    /// Reads an amount the way recipes write it: "2", "1,5", "1.5", "1/2", "1 1/2", "½" or "1½".
    public static func amount(from text: some StringProtocol) -> Double? {
        let fractions: [Character: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
        var total = 0.0
        for part in text.split(whereSeparator: \.isWhitespace) {
            var part = Substring(part)
            if let last = part.last, let fraction = fractions[last] {
                total += fraction
                part = part.dropLast()
                if part.isEmpty { continue }
            }
            if let slash = part.firstIndex(of: "/") {
                guard let numerator = Double(part[..<slash]),
                      let denominator = Double(part[part.index(after: slash)...]), denominator > 0 else { return nil }
                total += numerator / denominator
            } else if part.wholeMatch(of: #/[1-9]\d{0,2}\.\d{3}/#) != nil {
                // "1.000 g" is a thousand grams, the way German recipes write it.
                guard let value = Double(part.replacing(".", with: "")) else { return nil }
                total += value
            } else {
                guard let value = Double(part.replacing(",", with: ".")) else { return nil }
                total += value
            }
        }
        return total > 0 ? total : nil
    }
}

extension RecipeIngredient {
    /// Whether Mealie parsed this ingredient into amount, unit and food.
    private var hasStructuredQuantity: Bool {
        (quantity ?? 0) > 0 && (unit != nil || food != nil)
    }

    /// The amount scaling changes: Mealie's parsed quantity, or the number a free-text line starts with.
    public var scalableAmount: Double? {
        if hasStructuredQuantity { return quantity }
        return RecipeFormat.leadingAmount(in: text())?.values.first
    }

    /// Text for the ingredient list with its amount scaled by `factor`, split so the scaled amount
    /// can be highlighted. `amount` is nil when nothing was scaled.
    public func scaledText(by factor: Double) -> (before: String, amount: String?, after: String) {
        guard factor != 1 else { return ("", nil, text()) }
        if hasStructuredQuantity, let quantity {
            let unitName: String? = {
                guard let unit else { return nil }
                if unit.useAbbreviation == true, let abbreviation = unit.abbreviation?.nilIfBlank { return abbreviation }
                return unit.name
            }()
            let rest = [unitName, food?.name, note?.nilIfBlank].compactMap { $0 }.joined(separator: " ")
            return ("", RecipeFormat.quantity(quantity * factor), rest.isEmpty ? "" : " " + rest)
        }
        let line = text()
        guard let amount = RecipeFormat.leadingAmount(in: line) else { return ("", nil, line) }
        let scaled = amount.values.map { RecipeFormat.quantity($0 * factor) }.joined(separator: "–")
        return (String(line[..<amount.range.lowerBound]), scaled, String(line[amount.range.upperBound...]))
    }

    /// Text for the ingredient list, scaled by `factor`.
    public func text(scaledBy factor: Double) -> String {
        let parts = scaledText(by: factor)
        return parts.before + (parts.amount ?? "") + parts.after
    }

    /// Text for the ingredient list as Mealie shows it.
    public func text() -> String {
        display?.nilIfBlank ?? originalText?.nilIfBlank ?? note?.nilIfBlank ?? food?.name ?? ""
    }

    /// Mealie uses ingredients with only a title as section headers.
    public var isSectionHeader: Bool {
        title?.nilIfBlank != nil && text().isEmpty
    }
}

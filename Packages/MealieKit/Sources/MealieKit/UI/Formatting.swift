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
}

extension RecipeIngredient {
    /// Text for the ingredient list, scaled by `factor` when Mealie has structured data.
    public func text(scaledBy factor: Double = 1) -> String {
        if factor != 1, let quantity, quantity > 0, unit != nil || food != nil {
            let unitName: String? = {
                guard let unit else { return nil }
                if unit.useAbbreviation == true, let abbreviation = unit.abbreviation?.nilIfBlank { return abbreviation }
                return unit.name
            }()
            return [RecipeFormat.quantity(quantity * factor), unitName, food?.name, note?.nilIfBlank]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return display?.nilIfBlank ?? originalText?.nilIfBlank ?? note?.nilIfBlank ?? food?.name ?? ""
    }

    /// Mealie uses ingredients with only a title as section headers.
    public var isSectionHeader: Bool {
        title?.nilIfBlank != nil && text().isEmpty
    }
}

import Foundation

public enum ImportSource: Hashable, Sendable {
    /// A web page or video link. Mealie scrapes it and transcribes videos.
    case link(URL)
    /// Free text such as a pasted recipe, sent to Mealie AI.
    case text(String)
    /// JPEG photos of a recipe (cookbook page, screenshot), sent to Mealie AI.
    case photos([Data], note: String?)

    public var kind: SourceKind {
        switch self {
        case .link(let url): SourceKind(url: url)
        case .text: .text
        case .photos: .photos
        }
    }
}

public struct ImportOptions: Codable, Hashable, Sendable {
    public var includeTags: Bool
    public var includeCategories: Bool
    /// Mealie translates the finished recipe into this language. Nil keeps the source language.
    public var translateLanguage: String?
    /// Process photos and text with Apple's on-device model instead of sending them to Mealie AI.
    public var preferLocalAI: Bool

    public init(includeTags: Bool = true, includeCategories: Bool = false,
                translateLanguage: String? = nil, preferLocalAI: Bool = true) {
        self.includeTags = includeTags
        self.includeCategories = includeCategories
        self.translateLanguage = translateLanguage
        self.preferLocalAI = preferLocalAI
    }

    /// The same options, but forcing the server route.
    public var usingServerAI: ImportOptions {
        var copy = self
        copy.preferLocalAI = false
        return copy
    }

    public var translates: Bool {
        get { translateLanguage != nil }
        set { translateLanguage = newValue ? Self.deviceLanguage : nil }
    }

    /// The device language in English ("German"), which is what Mealie puts into its prompt.
    public static var deviceLanguage: String {
        guard let code = Locale.current.language.languageCode?.identifier else { return "English" }
        return Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
    }

    /// The same language in the user's own words, for labels ("Deutsch").
    public static var deviceLanguageLocalized: String {
        guard let code = Locale.current.language.languageCode?.identifier else { return "English" }
        return Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "English"
    }
}

public enum SourceKind: Hashable, Sendable {
    case youTubeShort, youTube, instagram, tikTok, website, text, photos

    public init(url: URL) {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path().lowercased()
        if host.hasSuffix("youtube.com") || host == "youtu.be" {
            self = path.hasPrefix("/shorts/") ? .youTubeShort : .youTube
        } else if host.hasSuffix("instagram.com") {
            self = .instagram
        } else if host.hasSuffix("tiktok.com") {
            self = .tikTok
        } else {
            self = .website
        }
    }

    public var title: String {
        switch self {
        case .youTubeShort: "YouTube Short"
        case .youTube: L("YouTube-Video")
        case .instagram: "Instagram"
        case .tikTok: "TikTok"
        case .website: L("Webseite")
        case .text: L("Text")
        case .photos: L("Fotos")
        }
    }

    public var systemImage: String {
        switch self {
        case .youTubeShort, .youTube, .instagram, .tikTok: "play.rectangle.fill"
        case .website: "safari.fill"
        case .text: "text.alignleft"
        case .photos: "photo.on.rectangle.angled"
        }
    }

    public var isVideo: Bool {
        switch self {
        case .youTubeShort, .youTube, .instagram, .tikTok: true
        default: false
        }
    }

    /// What the user should expect while Mealie works.
    public var durationHint: String {
        isVideo
            ? L("Mealie lädt das Video und transkribiert den Ton. Das dauert meist 20–60 Sekunden.")
            : L("Das dauert meist nur ein paar Sekunden.")
    }
}

extension URL {
    /// Removes tracking parameters like YouTube's `si=` before sending the link to Mealie.
    public var withoutTrackingParameters: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        let tracking: Set<String> = ["si", "feature", "igsh", "igshid", "utm_source", "utm_medium",
                                     "utm_campaign", "utm_term", "utm_content", "fbclid"]
        components.queryItems = components.queryItems?.filter { !tracking.contains($0.name.lowercased()) }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.url ?? self
    }

    /// Finds the first web link in shared text such as "Look at this! https://youtube.com/…".
    public static func firstWebLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}

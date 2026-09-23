import Foundation

/// Title, description and length of a YouTube video, from the official YouTube Data API.
public struct YouTubeVideoInfo: Sendable, Equatable {
    public var id: String
    public var title: String
    public var channel: String
    public var description: String
    public var durationSeconds: Int?
    public var thumbnailURL: URL?

    /// "18 Min." for the "analyse the whole video" option.
    public var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = durationSeconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(max(durationSeconds, 60)))
    }
}

public enum YouTubeError: LocalizedError {
    case invalidKey
    case quotaExceeded
    case notFound
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidKey: L("Der YouTube-API-Schlüssel ist ungültig.")
        case .quotaExceeded: L("Das Tageskontingent der YouTube-API ist aufgebraucht.")
        case .notFound: L("Das Video wurde nicht gefunden oder ist privat.")
        case .unavailable: L("YouTube ist gerade nicht erreichbar.")
        }
    }
}

/// The YouTube Data API key built into the app from Config/Secrets.xcconfig.
public enum YouTubeAPIKey {
    /// Nil when the build has no key; YouTube links then go straight to Mealie.
    public static var current: String? {
        guard let key = (Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String)?.nilIfBlank,
              !key.hasPrefix("$(") else { return nil }
        return key
    }
}

public enum YouTubeDataAPI {
    /// One `videos.list` call: costs 1 of the 10,000 free daily quota units.
    public static func video(id: String, apiKey: String, session: URLSession = .shared) async throws -> YouTubeVideoInfo {
        var url = URL(string: "https://www.googleapis.com/youtube/v3/videos")!
        url.append(queryItems: [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "key", value: apiKey)
        ])

        var request = URLRequest(url: url)
        // Lets Google enforce the key's restriction to this app's bundle IDs.
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let reason = String(decoding: data, as: UTF8.self)
            if reason.contains("quotaExceeded") { throw YouTubeError.quotaExceeded }
            if status == 400 || status == 403 { throw YouTubeError.invalidKey }
            throw YouTubeError.unavailable
        }

        struct Response: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable {
                    struct Thumbnail: Decodable { var url: URL }
                    var title: String
                    var channelTitle: String
                    var description: String
                    var thumbnails: [String: Thumbnail]?
                }
                struct ContentDetails: Decodable { var duration: String? }
                var id: String
                var snippet: Snippet
                var contentDetails: ContentDetails?
            }
            var items: [Item]
        }

        guard let item = try JSONDecoder().decode(Response.self, from: data).items.first else {
            throw YouTubeError.notFound
        }
        let thumbnails = item.snippet.thumbnails ?? [:]
        return YouTubeVideoInfo(
            id: item.id,
            title: item.snippet.title,
            channel: item.snippet.channelTitle,
            description: item.snippet.description,
            durationSeconds: item.contentDetails?.duration.flatMap(isoDurationSeconds),
            thumbnailURL: (thumbnails["maxres"] ?? thumbnails["high"] ?? thumbnails["medium"])?.url
        )
    }

    /// "PT1H2M3S" → 3723.
    static func isoDurationSeconds(_ iso: String) -> Int? {
        guard iso.hasPrefix("P") else { return nil }
        var total = 0, number = ""
        for character in iso.dropFirst() {
            if character.isNumber { number.append(character); continue }
            let value = Int(number) ?? 0
            number = ""
            switch character {
            case "D": total += value * 86_400
            case "H": total += value * 3600
            case "M": total += value * 60
            case "S": total += value
            default: continue
            }
        }
        return total
    }
}

extension URL {
    /// The video ID of any common YouTube link: watch, youtu.be, Shorts, live and embeds.
    public var youTubeVideoID: String? {
        guard let host = host()?.lowercased() else { return nil }
        let parts = pathComponents.filter { $0 != "/" }
        if host == "youtu.be" { return parts.first }
        guard host.hasSuffix("youtube.com") else { return nil }
        if parts.first == "watch" {
            return URLComponents(url: self, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "v" }?.value
        }
        if let first = parts.first, ["shorts", "live", "embed"].contains(first), parts.count > 1 {
            return parts[1]
        }
        return nil
    }
}

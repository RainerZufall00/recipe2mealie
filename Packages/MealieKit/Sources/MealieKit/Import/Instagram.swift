import Foundation

/// The caption of a public Instagram post or reel, as a logged-out visitor sees it.
///
/// Instagram has no public API for other people's posts and no access to its auto-captions, so
/// this reads the embed page Instagram offers to third-party sites, with the post page's Open
/// Graph text as fallback. Both are rate-limited for anonymous visitors: nil now may work later.
public enum InstagramPost {
    public static func caption(for url: URL, session: URLSession = .shared) async -> VideoInfo? {
        guard let code = url.instagramShortcode else { return nil }
        if let html = await page("https://www.instagram.com/p/\(code)/embed/captioned/", session: session),
           let info = embedCaption(in: html, code: code) {
            return info
        }
        if let html = await page("https://www.instagram.com/p/\(code)/", session: session),
           let info = openGraphCaption(in: html, code: code) {
            return info
        }
        log.notice("No Instagram caption for \(code, privacy: .public)")
        return nil
    }

    private static func page(_ address: String, session: URLSession) async -> String? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Keeps the Open Graph text in one predictable format ("… - user on date: "caption"").
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.path().hasPrefix("/accounts/login") != true else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `<div class="Caption"><a class="CaptionUsername">user</a><br />Caption…<div class="CaptionComments">`
    static func embedCaption(in html: String, code: String) -> VideoInfo? {
        guard let match = html.firstMatch(of: /class="Caption">(.*?)<div class="CaptionComments/.dotMatchesNewlines())
        else { return nil }
        var caption = String(match.1)
        var user = ""
        if let name = caption.firstMatch(of: /<a class="CaptionUsername"[^>]*>(.*?)<\/a>/) {
            user = plainText(String(name.1))
            caption.removeSubrange(name.range)
        }
        return info(code: code, user: user, caption: plainText(caption))
    }

    /// `<meta property="og:description" content="12K likes, 80 comments - user on October 1, 2026: &quot;Caption…&quot;. ">`
    static func openGraphCaption(in html: String, code: String) -> VideoInfo? {
        guard let match = html.firstMatch(of: /property="og:description" content="([^"]*)"/) else { return nil }
        let content = plainText(String(match.1))
        guard let start = content.range(of: ": \""), let end = content.range(of: "\"", options: .backwards),
              start.upperBound < end.lowerBound else { return nil }
        let header = content[..<start.lowerBound]
        let user = header.components(separatedBy: " - ").last?.split(separator: " ").first.map(String.init) ?? ""
        return info(code: code, user: user, caption: String(content[start.upperBound..<end.lowerBound]))
    }

    private static func info(code: String, user: String, caption: String) -> VideoInfo? {
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caption.isEmpty else { return nil }
        return VideoInfo(id: code, title: "", channel: user.isEmpty ? "Instagram" : "@\(user)",
                         description: caption, durationSeconds: nil, thumbnailURL: nil)
    }

    static func plainText(_ html: String) -> String {
        html.replacing(/<br\s*\/?>/, with: "\n")
            .replacing(/<[^>]+>/, with: "")
            .decodingHTMLEntities()
            .replacing("\u{2063}", with: "") // invisible separator Instagram puts on "empty" lines
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension URL {
    /// "DePb6WLuVae" from /reel/…, /reels/…, /p/…, /tv/… and /{user}/reel/… links.
    public var instagramShortcode: String? {
        guard host()?.lowercased().hasSuffix("instagram.com") == true else { return nil }
        let parts = pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { ["reel", "reels", "p", "tv"].contains($0) }),
              parts.indices.contains(index + 1) else { return nil }
        return parts[index + 1]
    }
}

extension String {
    /// Named basics plus numeric entities like `&#064;` or `&#x1f43e;`.
    func decodingHTMLEntities() -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
        return replacing(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/) { match in
            let body = String(match.1)
            let scalar: UInt32? = if body.hasPrefix("#x") || body.hasPrefix("#X") {
                UInt32(body.dropFirst(2), radix: 16)
            } else if body.hasPrefix("#") {
                UInt32(body.dropFirst())
            } else {
                nil
            }
            if let scalar, let character = Unicode.Scalar(scalar) { return String(character) }
            return named[body] ?? String(match.0)
        }
    }
}

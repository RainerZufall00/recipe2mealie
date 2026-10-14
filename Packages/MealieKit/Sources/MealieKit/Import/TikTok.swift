import Foundation

/// The caption of a public TikTok video, from TikTok's official oEmbed endpoint (no key, no login).
/// TikTok removes the line breaks, so the caption arrives as one long line.
public enum TikTokPost {
    public static func caption(for url: URL, session: URLSession = .shared) async -> VideoInfo? {
        guard let videoURL = await videoURL(for: url, session: session) else { return nil }
        struct OEmbed: Decodable {
            var title: String?
            var author_unique_id: String?
        }
        var endpoint = URL(string: "https://www.tiktok.com/oembed")!
        endpoint.append(queryItems: [URLQueryItem(name: "url", value: videoURL.absoluteString)])
        guard let (data, response) = try? await session.data(from: endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let oembed = try? JSONDecoder().decode(OEmbed.self, from: data),
              let caption = oembed.title?.nilIfBlank else {
            log.notice("No TikTok caption for \(videoURL.absoluteString, privacy: .public)")
            return nil
        }
        return VideoInfo(id: videoURL.lastPathComponent, title: "",
                         channel: oembed.author_unique_id.map { "@\($0)" } ?? "TikTok",
                         description: caption, durationSeconds: nil, thumbnailURL: nil)
    }

    /// Share links (vm.tiktok.com/…, tiktok.com/t/…) only redirect to the video, which oEmbed needs.
    private static func videoURL(for url: URL, session: URLSession) async -> URL? {
        if url.isTikTokVideo { return url }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (_, response) = try? await session.data(for: request),
              let resolved = response.url, resolved.isTikTokVideo else { return nil }
        return resolved
    }
}

extension URL {
    var isTikTokVideo: Bool {
        host()?.lowercased().hasSuffix("tiktok.com") == true && pathComponents.contains("video")
    }
}

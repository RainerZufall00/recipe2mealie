import Foundation
import LinkPresentation
import UIKit

/// Title, author and thumbnail for a shared link, shown before and during the import.
public struct LinkPreview: Sendable {
    public var title: String?
    public var subtitle: String?
    public var imageURL: URL?
    public var imageData: Data?

    static func load(for url: URL) async -> LinkPreview? {
        if SourceKind(url: url) == .youTube || SourceKind(url: url) == .youTubeShort,
           let preview = await youTubeOEmbed(for: url) {
            return preview
        }
        return await linkPresentation(for: url)
    }

    /// YouTube's public oEmbed endpoint: no API key, returns title, channel and thumbnail.
    private static func youTubeOEmbed(for url: URL) async -> LinkPreview? {
        struct OEmbed: Decodable {
            var title: String?
            var author_name: String?
            var thumbnail_url: URL?
        }
        var endpoint = URL(string: "https://www.youtube.com/oembed")!
        endpoint.append(queryItems: [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ])
        guard let (data, response) = try? await URLSession.shared.data(from: endpoint),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let oembed = try? JSONDecoder().decode(OEmbed.self, from: data) else { return nil }
        return LinkPreview(title: oembed.title, subtitle: oembed.author_name, imageURL: oembed.thumbnail_url)
    }

    @MainActor
    private static func linkPresentation(for url: URL) async -> LinkPreview? {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else {
            return LinkPreview(title: nil, subtitle: url.host(), imageURL: nil)
        }
        var preview = LinkPreview(title: metadata.title, subtitle: url.host(), imageURL: nil)
        if let imageProvider = metadata.imageProvider {
            preview.imageData = await withCheckedContinuation { continuation in
                _ = imageProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    continuation.resume(returning: (image as? UIImage)?.jpegData(compressionQuality: 0.8))
                }
            }
        }
        return preview
    }
}

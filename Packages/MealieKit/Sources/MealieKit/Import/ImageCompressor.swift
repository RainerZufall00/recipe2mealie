import UIKit

public enum ImageCompressor {
    /// Downscales photos before upload so a cookbook page doesn't send 10 MB to Mealie.
    public static func jpegForUpload(_ data: Data, maxDimension: CGFloat = 2048) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpegForUpload(image, maxDimension: maxDimension)
    }

    public static func jpegForUpload(_ image: UIImage, maxDimension: CGFloat = 2048) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image.jpegData(compressionQuality: 0.85) }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

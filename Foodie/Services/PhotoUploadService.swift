import Foundation
import UIKit
import Supabase

// Uploads review photos to Supabase Storage.
//
// Images are downscaled and re-encoded on device before upload. Egress is the
// quota Foodie would realistically outgrow first — a handful of full-resolution
// iPhone photos is tens of megabytes, and every view of them counts again — so
// shrinking here is what keeps the free tier viable.
enum PhotoUploadService {

    static let bucket = "review-photos"

    // 1600px on the long edge still looks sharp on a Pro Max at full width,
    // and turns a ~5 MB original into roughly 200–400 KB.
    private static let maxDimension: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.8

    // Returns the storage path to record on the review.
    static func upload(_ image: UIImage, userId: UUID) async throws -> String {
        guard let data = downscaledJPEG(image) else {
            throw PhotoUploadError.encodingFailed
        }

        // The first path segment must be the user's id — the bucket's INSERT
        // policy checks exactly that, so this shape is load-bearing.
        let path = "\(userId.uuidString)/\(UUID().uuidString).jpg"

        try await SupabaseService.client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg")
            )

        return path
    }

    // The bucket is public, so this is a plain CDN URL with no round trip.
    static func publicURL(for path: String) -> URL? {
        try? SupabaseService.client.storage.from(bucket).getPublicURL(path: path)
    }

    // MARK: - Resizing

    static func downscaledJPEG(_ image: UIImage) -> Data? {
        let resized = downscaled(image)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image }

        let scale = maxDimension / longEdge
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        // scale = 1 keeps the output in points-as-pixels; without it the
        // renderer would multiply by the device scale and undo the downscale.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

enum PhotoUploadError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "That photo couldn't be prepared for upload."
    }
}

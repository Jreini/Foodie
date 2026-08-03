import Foundation
import UIKit
import Supabase

// Uploads images to Supabase Storage — review photos and profile avatars.
//
// Images are downscaled and re-encoded on device before upload. Egress is the
// quota Foodie would realistically outgrow first — a handful of full-resolution
// iPhone photos is tens of megabytes, and every view of them counts again — so
// shrinking here is what keeps the free tier viable.
enum PhotoUploadService {

    static let reviewBucket = "review-photos"
    static let avatarBucket = "avatars"

    // 1600px on the long edge still looks sharp on a Pro Max at full width,
    // and turns a ~5 MB original into roughly 200–400 KB.
    private static let reviewMaxDimension: CGFloat = 1600
    private static let reviewQuality: CGFloat = 0.8

    // Avatars are never shown larger than ~80pt, so 512px covers a 3x screen
    // with room to spare. Bigger would only cost egress on every feed row.
    private static let avatarMaxDimension: CGFloat = 512
    private static let avatarQuality: CGFloat = 0.85

    // MARK: - Review photos

    // Returns the storage path to record on the review.
    static func upload(_ image: UIImage, userId: UUID) async throws -> String {
        try await upload(
            image,
            userId: userId,
            bucket: reviewBucket,
            maxDimension: reviewMaxDimension,
            quality: reviewQuality
        )
    }

    // The bucket is public, so this is a plain CDN URL with no round trip.
    static func publicURL(for path: String) -> URL? {
        publicURL(for: path, in: reviewBucket)
    }

    // MARK: - Avatars

    // Returns the storage path to record on the profile row.
    static func uploadAvatar(_ image: UIImage, userId: UUID) async throws -> String {
        try await upload(
            image,
            userId: userId,
            bucket: avatarBucket,
            maxDimension: avatarMaxDimension,
            quality: avatarQuality
        )
    }

    static func avatarURL(for path: String) -> URL? {
        publicURL(for: path, in: avatarBucket)
    }

    // Best effort: a replaced avatar whose old file survives is wasted storage,
    // not a broken profile, and failing the whole edit over it would be worse.
    static func removeAvatar(at path: String) async {
        do {
            _ = try await SupabaseService.client.storage
                .from(avatarBucket)
                .remove(paths: [path])
        } catch {
            #if DEBUG
            print("[Foodie] couldn't remove old avatar \(path): \(error)")
            #endif
        }
    }

    // MARK: - Upload

    private static func upload(
        _ image: UIImage,
        userId: UUID,
        bucket: String,
        maxDimension: CGFloat,
        quality: CGFloat
    ) async throws -> String {
        guard let data = downscaledJPEG(image, maxDimension: maxDimension, quality: quality) else {
            throw PhotoUploadError.encodingFailed
        }

        // The first path segment must be the user's id — both buckets' INSERT
        // policies check exactly that, so this shape is load-bearing.
        //
        // Lowercased deliberately: Swift renders UUIDs uppercase while Postgres
        // renders `auth.uid()::text` lowercase, so an unmodified uuidString
        // never matches the policy and every upload 403s.
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"

        try await SupabaseService.client.storage
            .from(bucket)
            .upload(
                path,
                data: data,
                options: FileOptions(
                    // A fresh UUID per upload means a path never points at
                    // different bytes than it did before, so it's safe to let
                    // caches hold it for a long time. Replacing an avatar
                    // produces a new path, which is what busts the old one.
                    cacheControl: "31536000",
                    contentType: "image/jpeg"
                )
            )

        return path
    }

    private static func publicURL(for path: String, in bucket: String) -> URL? {
        try? SupabaseService.client.storage.from(bucket).getPublicURL(path: path)
    }

    // MARK: - Resizing

    private static func downscaledJPEG(
        _ image: UIImage,
        maxDimension: CGFloat,
        quality: CGFloat
    ) -> Data? {
        downscaled(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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

import Foundation

struct User: Identifiable, Hashable {
    let id: UUID
    var name: String
    var username: String
    // Object path in the public `avatars` bucket, nil until a picture is
    // uploaded. A path rather than a URL for the same reason the column is —
    // the CDN host isn't part of the identity. `ProfileImageView` turns it into
    // an image and falls back to a symbol when it's nil.
    var avatarPath: String?
    var bio: String
    var joinDate: Date
    // Only ever populated for the signed-in user: the friendships policy hides
    // other people's edges, so a friend's own count comes from `friendCount()`
    // server-side instead.
    var friendIds: [UUID]

    // Computed convenience properties
    var friendCount: Int { friendIds.count }
}

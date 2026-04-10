import Foundation

struct Review: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let restaurantId: UUID
    var rating: Int
    var text: String
    var moodTags: [String]
    var photoNames: [String]
    var createdAt: Date

    // Clamp rating between 1 and 5
    var clampedRating: Int {
        min(max(rating, 1), 5)
    }
}

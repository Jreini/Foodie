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
    // Reviewer's tier placement for this restaurant on the 0-1 spectrum.
    // A 5-star here is interpreted WITHIN this tier (e.g. top-shelf fast food
    // is different from top-shelf fine dining).
    var tierPlacement: RestaurantTier

    // Clamp rating between 1 and 5
    var clampedRating: Int {
        min(max(rating, 1), 5)
    }
}

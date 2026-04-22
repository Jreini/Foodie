import Foundation

struct Restaurant: Identifiable, Hashable {
    let id: UUID
    var name: String
    var cuisineType: String
    var address: String
    var latitude: Double
    var longitude: Double
    var averageRating: Double
    // 1 = $, 2 = $$, 3 = $$$, 4 = $$$$
    var priceLevel: Int
    var imageName: String
    var hoursDescription: String
    var tags: [String]
    var isOpenNow: Bool

    // Preset tier baseline — acts as the seed before any user placements exist
    var baselineTier: RestaurantTier
    // Crowd-adjusted tier — derived from baseline + all user placements.
    // Stored (rather than computed) so rows/cards don't have to re-aggregate.
    var averageTier: RestaurantTier

    // Formatted price string (e.g. "$$$")
    var priceLevelString: String {
        String(repeating: "$", count: priceLevel)
    }
}

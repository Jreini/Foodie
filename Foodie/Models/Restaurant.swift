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

    // Formatted price string (e.g. "$$$")
    var priceLevelString: String {
        String(repeating: "$", count: priceLevel)
    }
}

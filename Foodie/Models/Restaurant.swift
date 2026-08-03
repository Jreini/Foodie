import Foundation
import CoreLocation

struct Restaurant: Identifiable, Hashable {
    let id: UUID
    // MapKit's stable place identifier. Nil for the starter rows seeded in
    // Phase 3, which predate MapKit search.
    var mapkitPlaceId: String? = nil
    var name: String
    var cuisineType: String
    var address: String
    var latitude: Double
    var longitude: Double
    var averageRating: Double
    // 1 = $, 2 = $$, 3 = $$$, 4 = $$$$. Nil when unknown: MapKit reports no
    // price data, so a search result genuinely has none rather than "$".
    var priceLevel: Int?
    var imageName: String
    // Nil when unknown — MapKit doesn't expose opening hours on a map item.
    var hoursDescription: String?
    var tags: [String]
    // Nil when unknown, for the same reason as hours.
    var isOpenNow: Bool?

    // Preset tier baseline — acts as the seed before any user placements exist
    var baselineTier: RestaurantTier
    // Crowd-adjusted tier — derived from baseline + all user placements.
    // Stored (rather than computed) so rows/cards don't have to re-aggregate.
    var averageTier: RestaurantTier

    // False for a MapKit result that has no row in Postgres yet. Interacting
    // with one (review, like, tasting list) is what creates the row.
    var isPersisted: Bool = true

    // Formatted price string (e.g. "$$$"), empty when the price is unknown.
    var priceLevelString: String {
        guard let priceLevel else { return "" }
        return String(repeating: "$", count: priceLevel)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Restaurant {
    // Combines a MapKit search result (self) with the database row for the same
    // place. The row wins on identity and crowd data, because it's the source of
    // truth for both. MapKit wins on the descriptive fields, which it keeps
    // fresher than a row written whenever someone first tapped the place.
    func merging(persisted row: Restaurant) -> Restaurant {
        Restaurant(
            id: row.id,
            mapkitPlaceId: mapkitPlaceId ?? row.mapkitPlaceId,
            name: name,
            cuisineType: cuisineType,
            address: address,
            latitude: latitude,
            longitude: longitude,
            averageRating: row.averageRating,
            priceLevel: priceLevel ?? row.priceLevel,
            imageName: imageName,
            hoursDescription: hoursDescription ?? row.hoursDescription,
            tags: tags.isEmpty ? row.tags : tags,
            isOpenNow: isOpenNow ?? row.isOpenNow,
            baselineTier: row.baselineTier,
            averageTier: row.averageTier,
            isPersisted: true
        )
    }
}

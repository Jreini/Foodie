import Foundation
import MapKit
import CryptoKit

// Restaurant discovery via MapKit.
//
// Free with the developer account — no per-request billing, which is why this
// is MapKit rather than Google Places. The trade-off is thinner data: MapKit
// gives name, location, address, and a coarse category, but no price, hours,
// ratings, or photos. Those fields stay nil rather than being invented, and
// Foodie's own reviews are what fill the gap.
enum PlaceSearchService {

    // Everywhere you'd eat or drink. Deliberately excludes things like
    // gas stations that MapKit would otherwise return for "food".
    private static let foodCategories: [MKPointOfInterestCategory] = [
        .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket
    ]

    static func searchRestaurants(
        matching query: String?,
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 5_000
    ) async throws -> [Restaurant] {
        let request = MKLocalSearchRequest()

        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // An empty query returns nothing, so an unfiltered browse asks for the
        // generic term and lets the category filter do the narrowing.
        request.naturalLanguageQuery = trimmed.isEmpty ? "restaurant" : trimmed

        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: foodCategories)

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap(restaurant(from:))
    }

    // MARK: - Mapping

    static func restaurant(from item: MKMapItem) -> Restaurant? {
        // Without a stable identifier there's no way to match this to a
        // database row later, so it isn't usable.
        guard let placeId = item.identifier?.rawValue, let name = item.name else {
            return nil
        }

        let category = item.pointOfInterestCategory
        let tier = baselineTier(for: category)

        return Restaurant(
            id: derivedId(for: placeId),
            mapkitPlaceId: placeId,
            name: name,
            cuisineType: categoryLabel(for: category),
            address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            // Crowd values stay at zero until this is merged with a database
            // row that has real reviews behind it.
            averageRating: 0,
            priceLevel: nil,
            imageName: "fork.knife.circle.fill",
            hoursDescription: nil,
            tags: [],
            isOpenNow: nil,
            baselineTier: tier,
            averageTier: tier,
            isPersisted: false
        )
    }

    // Seeds where a place sits on the spectrum before anyone has placed it.
    // MapKit's categories are coarse — there's no fast-food category at all —
    // so this only has to be a defensible starting point. The first real
    // placement starts pulling the average toward the truth.
    static func baselineTier(for category: MKPointOfInterestCategory?) -> RestaurantTier {
        switch category {
        case .some(.foodMarket): return RestaurantTier(0.10)
        case .some(.bakery):     return RestaurantTier(0.20)
        case .some(.cafe):       return RestaurantTier(0.25)
        case .some(.brewery):    return RestaurantTier(0.45)
        case .some(.restaurant): return RestaurantTier(0.50)
        case .some(.winery):     return RestaurantTier(0.70)
        default:                 return RestaurantTier(0.50)
        }
    }

    private static func categoryLabel(for category: MKPointOfInterestCategory?) -> String {
        switch category {
        case .some(.foodMarket): return "Food Market"
        case .some(.bakery):     return "Bakery"
        case .some(.cafe):       return "Café"
        case .some(.brewery):    return "Brewery"
        case .some(.winery):     return "Winery"
        case .some(.restaurant): return "Restaurant"
        default:                 return "Restaurant"
        }
    }

    // MARK: - Identity

    // A MapKit result needs an id before it exists in the database — SwiftUI
    // navigation and `Identifiable` both depend on one. Deriving it from the
    // place identifier makes it stable across launches and devices, so two
    // people looking at the same restaurant agree on it.
    //
    // UUIDv5-style: namespaced hash with the version and variant bits set.
    // The database still upserts on mapkit_place_id, so this is a handle
    // rather than the authority on identity.
    private static func derivedId(for placeId: String) -> UUID {
        let seed = Data("foodie.mapkit:\(placeId)".utf8)
        var bytes = Array(SHA256.hash(data: seed).prefix(16))

        bytes[6] = (bytes[6] & 0x0F) | 0x50  // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 4122 variant

        return UUID(uuid: (
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],  bytes[6],  bytes[7],
            bytes[8],  bytes[9],  bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

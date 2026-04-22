import Foundation

// Evaluates whether a user's tier placement is a statistical outlier relative
// to a restaurant's current average tier. If so, the UI should prompt the user
// to confirm (e.g. placing McDonald's in Fine Dining).
enum TierFlaggingService {

    // Minimum absolute distance on the 0-1 spectrum before a placement is
    // even considered suspicious. Tuned to roughly "one named-zone width".
    static let distanceThreshold: Double = 0.25

    // Placements on brand-new restaurants (no reviews yet) are never flagged,
    // since there's no crowd signal to compare against.
    static let minReviewsForFlagging: Int = 1

    // Result of a flag evaluation. When shouldFlag is true the UI presents
    // a confirmation alert using suggestedMessage.
    struct FlagResult: Equatable {
        let shouldFlag: Bool
        let distance: Double
        let placedZone: RestaurantTier.Zone
        let averageZone: RestaurantTier.Zone
        let suggestedMessage: String
    }

    // Decide whether a given placement should trigger a confirmation prompt.
    // - Parameters:
    //   - placement: the tier the user just selected
    //   - averageTier: the restaurant's current crowd-adjusted tier
    //   - restaurantName: used to personalize the message
    //   - existingReviewCount: how many placements already back the average
    static func evaluate(
        placement: RestaurantTier,
        averageTier: RestaurantTier,
        restaurantName: String,
        existingReviewCount: Int
    ) -> FlagResult {
        let distance = placement.distance(to: averageTier)
        let placedZone = placement.zone
        let avgZone = averageTier.zone

        // Flag when: enough data exists, distance exceeds threshold, AND the
        // user has crossed into a non-adjacent named zone. The "non-adjacent"
        // check suppresses flags for natural slight overlaps at zone edges.
        let hasEnoughData = existingReviewCount >= minReviewsForFlagging
        let farEnough = distance >= distanceThreshold
        let zonesFarApart = zoneDistance(placedZone, avgZone) >= 2

        let shouldFlag = hasEnoughData && farEnough && zonesFarApart

        let message = makeMessage(
            restaurantName: restaurantName,
            placedZone: placedZone,
            averageZone: avgZone
        )

        return FlagResult(
            shouldFlag: shouldFlag,
            distance: distance,
            placedZone: placedZone,
            averageZone: avgZone,
            suggestedMessage: message
        )
    }

    // Recompute the crowd-adjusted averageTier for a restaurant.
    // The baseline is included as a weighted "phantom placement" so that
    // restaurants without many reviews don't swing wildly from one rating.
    static func recomputeAverageTier(
        baseline: RestaurantTier,
        placements: [RestaurantTier],
        baselineWeight: Double = 3.0
    ) -> RestaurantTier {
        // Weighted mean: baseline acts as `baselineWeight` virtual placements
        let baselineSum = baseline.value * baselineWeight
        let placementSum = placements.reduce(0.0) { $0 + $1.value }
        let totalWeight = baselineWeight + Double(placements.count)
        guard totalWeight > 0 else { return baseline }
        return RestaurantTier((baselineSum + placementSum) / totalWeight)
    }

    // MARK: - Helpers

    // How many zone "steps" apart two zones are on the ordered spectrum
    private static func zoneDistance(
        _ a: RestaurantTier.Zone,
        _ b: RestaurantTier.Zone
    ) -> Int {
        let all = RestaurantTier.Zone.allCases
        guard let i = all.firstIndex(of: a),
              let j = all.firstIndex(of: b) else { return 0 }
        return abs(i - j)
    }

    // Build a friendly confirmation message referencing the specific zones
    private static func makeMessage(
        restaurantName: String,
        placedZone: RestaurantTier.Zone,
        averageZone: RestaurantTier.Zone
    ) -> String {
        "You placed \(restaurantName) in the \(placedZone.shortLabel) tier, " +
        "but most people rate it as \(averageZone.shortLabel). " +
        "Is that really where you meant to place it?"
    }
}

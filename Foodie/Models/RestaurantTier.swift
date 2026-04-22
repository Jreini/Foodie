import Foundation
import SwiftUI

// Continuous restaurant tier on a 0.0 (Fast Food) -> 1.0 (Fine Dining) spectrum.
// The value is intentionally a Double so placements can fall anywhere between the
// named anchor zones, naturally expressing overlap between categories.
struct RestaurantTier: Hashable, Codable {

    // Normalized position on the spectrum, clamped to [0, 1].
    var value: Double

    init(_ value: Double) {
        // Clamp to valid range so downstream math never breaks
        self.value = min(max(value, 0.0), 1.0)
    }

    // MARK: - Named Zones

    // Named zones along the spectrum. Each zone owns a sub-range of [0, 1].
    // The overlap zones (fastCasual, upscaleCasual) sit between the primary
    // three tiers to express restaurants that straddle categories.
    enum Zone: String, CaseIterable, Hashable {
        case fastFood       = "Fast Food"
        case fastCasual     = "Fast-Casual"
        case casualDining   = "Casual Dining"
        case upscaleCasual  = "Upscale Casual"
        case fineDining     = "Fine Dining"

        // Inclusive-lower, exclusive-upper range for each zone on [0, 1]
        var range: ClosedRange<Double> {
            switch self {
            case .fastFood:      return 0.00...0.15
            case .fastCasual:    return 0.15...0.40
            case .casualDining:  return 0.40...0.65
            case .upscaleCasual: return 0.65...0.85
            case .fineDining:    return 0.85...1.00
            }
        }

        // Short label used in compact UI (badges, chips)
        var shortLabel: String {
            switch self {
            case .fastFood:      return "Fast Food"
            case .fastCasual:    return "Fast-Casual"
            case .casualDining:  return "Casual"
            case .upscaleCasual: return "Upscale"
            case .fineDining:    return "Fine Dining"
            }
        }

        // Accent color used to visually differentiate zones
        var accentColor: Color {
            switch self {
            case .fastFood:      return Color(red: 0.95, green: 0.55, blue: 0.25)
            case .fastCasual:    return Color(red: 0.95, green: 0.70, blue: 0.20)
            case .casualDining:  return Color(red: 0.40, green: 0.75, blue: 0.45)
            case .upscaleCasual: return Color(red: 0.35, green: 0.60, blue: 0.80)
            case .fineDining:    return Color(red: 0.55, green: 0.35, blue: 0.75)
            }
        }
    }

    // Primary zone this tier falls into based on its value
    var zone: Zone {
        // Walk zones in order; the first range that contains value wins
        for zone in Zone.allCases where zone.range.contains(value) {
            return zone
        }
        // Fallback (should be unreachable because ranges cover [0, 1])
        return value < 0.5 ? .fastFood : .fineDining
    }

    // Human-readable description, including overlap hints when value sits
    // near a zone boundary (within 0.05 of an edge).
    var descriptiveLabel: String {
        let z = zone
        let range = z.range
        let nearLower = (value - range.lowerBound) < 0.05
        let nearUpper = (range.upperBound - value) < 0.05

        // If close to a neighboring zone, describe the overlap
        if nearLower, let prev = z.previousZone {
            return "\(z.shortLabel) (leaning \(prev.shortLabel))"
        }
        if nearUpper, let next = z.nextZone {
            return "\(z.shortLabel) (leaning \(next.shortLabel))"
        }
        return z.shortLabel
    }

    // MARK: - Convenience Constructors

    // Build a tier at the center of a named zone (useful for defaults/seed data)
    static func centered(on zone: Zone) -> RestaurantTier {
        let mid = (zone.range.lowerBound + zone.range.upperBound) / 2.0
        return RestaurantTier(mid)
    }

    // Absolute spectrum distance between two tiers in [0, 1] units
    func distance(to other: RestaurantTier) -> Double {
        abs(self.value - other.value)
    }
}

// MARK: - Zone Navigation

extension RestaurantTier.Zone {
    // Previous zone (toward Fast Food) in the ordered spectrum
    var previousZone: RestaurantTier.Zone? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }

    // Next zone (toward Fine Dining) in the ordered spectrum
    var nextZone: RestaurantTier.Zone? {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self), idx < all.count - 1 else { return nil }
        return all[idx + 1]
    }
}

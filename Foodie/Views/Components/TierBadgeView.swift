import SwiftUI

// Compact pill showing a restaurant's (or placement's) tier zone. Used on
// restaurant rows, cards, and review cards so the rating always carries its
// tier context ("5 stars of WHAT?").
struct TierBadgeView: View {
    let tier: RestaurantTier
    var style: Style = .filled

    // Visual variants for different contexts (filled for detail, subtle for rows)
    enum Style {
        case filled
        case subtle
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9))
            Text(tier.zone.shortLabel)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(Capsule())
    }

    // Background varies by style so the badge adapts to light/dark surfaces
    private var background: some View {
        Group {
            switch style {
            case .filled:
                tier.zone.accentColor
            case .subtle:
                tier.zone.accentColor.opacity(0.18)
            }
        }
    }

    private var foreground: Color {
        switch style {
        case .filled:  return .white
        case .subtle:  return tier.zone.accentColor
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        TierBadgeView(tier: RestaurantTier(0.08))
        TierBadgeView(tier: RestaurantTier(0.30), style: .subtle)
        TierBadgeView(tier: RestaurantTier(0.55))
        TierBadgeView(tier: RestaurantTier(0.75), style: .subtle)
        TierBadgeView(tier: RestaurantTier(0.95))
    }
    .padding()
}

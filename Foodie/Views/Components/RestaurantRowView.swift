import SwiftUI

// Compact horizontal row for showing a restaurant in lists
struct RestaurantRowView: View {
    let restaurant: Restaurant

    var body: some View {
        HStack(spacing: AppTheme.spacingMD) {
            // Restaurant icon placeholder
            Image(systemName: restaurant.imageName)
                .font(.title2)
                .foregroundStyle(AppTheme.primaryColor)
                .frame(width: 50, height: 50)
                .background(AppTheme.primaryLight.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(restaurant.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: AppTheme.spacingSM) {
                    Text(restaurant.cuisineType)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text("·")
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(restaurant.priceLevelString)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                NumericRatingView(rating: restaurant.averageRating)
                // Tier badge contextualizes the numeric rating
                TierBadgeView(tier: restaurant.averageTier, style: .subtle)
            }
        }
        .padding(.vertical, AppTheme.spacingXS)
    }
}

#Preview {
    RestaurantRowView(restaurant: Restaurant(
        id: UUID(), name: "Sakura Sushi", cuisineType: "Japanese",
        address: "123 Cherry Blossom Ln", latitude: 0, longitude: 0,
        averageRating: 4.5, priceLevel: 3, imageName: "fork.knife.circle.fill",
        hoursDescription: "11 AM – 10 PM", tags: ["date night"], isOpenNow: true,
        baselineTier: RestaurantTier(0.72),
        averageTier: RestaurantTier(0.72)
    ))
    .padding()
}

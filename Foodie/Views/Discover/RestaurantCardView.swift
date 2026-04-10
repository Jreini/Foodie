import SwiftUI

// Visual card for a restaurant shown in the discover grid
struct RestaurantCardView: View {
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            // Restaurant image placeholder
            ZStack(alignment: .topTrailing) {
                Image(systemName: restaurant.imageName)
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))

                // Open/closed badge
                if restaurant.isOpenNow {
                    Text("Open")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(AppTheme.spacingSM)
                }
            }

            // Restaurant name
            Text(restaurant.name)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            // Cuisine + price
            HStack {
                Text(restaurant.cuisineType)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                Text(restaurant.priceLevelString)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // Rating
            NumericRatingView(rating: restaurant.averageRating, starSize: 11)
        }
        .padding(AppTheme.spacingMD)
        .cardStyle()
    }
}

#Preview {
    RestaurantCardView(restaurant: Restaurant(
        id: UUID(), name: "Sakura Sushi", cuisineType: "Japanese",
        address: "123 Cherry Blossom Ln", latitude: 0, longitude: 0,
        averageRating: 4.5, priceLevel: 3, imageName: "fork.knife.circle.fill",
        hoursDescription: "11 AM – 10 PM", tags: ["date night"], isOpenNow: true
    ))
    .frame(width: 180)
    .padding()
}

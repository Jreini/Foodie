import SwiftUI

// Displays a row of filled/empty stars for a given rating
struct StarRatingView: View {
    let rating: Int
    var maxRating: Int = 5
    var starSize: CGFloat = 14
    var color: Color = AppTheme.ratingColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: starSize))
                    .foregroundStyle(star <= rating ? color : Color.gray.opacity(0.3))
            }
        }
    }
}

// Displays a numeric rating with a single star icon (e.g. "4.5 ★")
struct NumericRatingView: View {
    let rating: Double
    var starSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: starSize))
                .foregroundStyle(AppTheme.ratingColor)
            Text(String(format: "%.1f", rating))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StarRatingView(rating: 4)
        StarRatingView(rating: 2, maxRating: 5, starSize: 20)
        NumericRatingView(rating: 4.5)
    }
    .padding()
}

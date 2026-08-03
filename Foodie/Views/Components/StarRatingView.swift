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

// Tappable star picker.
//
// Each star is its own button. The previous version put a single tap gesture
// over the whole row and derived the rating from the touch's x position
// divided by an assumed star width — which broke inside a Form, where the row
// is far wider than the stars themselves. The leading offset pushed every tap
// past the fifth star, so any tap produced a 5.
struct StarRatingInput: View {
    @Binding var rating: Int
    var maxRating: Int = 5
    var starSize: CGFloat = 28
    var color: Color = AppTheme.ratingColor

    var body: some View {
        HStack(spacing: AppTheme.spacingSM) {
            ForEach(1...maxRating, id: \.self) { star in
                Button {
                    rating = star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: starSize))
                        .foregroundStyle(star <= rating ? color : Color.gray.opacity(0.3))
                        // Padded hit area: the glyph alone is a small target,
                        // and contentShape makes the gaps tappable too.
                        .frame(width: starSize + 14, height: starSize + 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
            }
        }
        .animation(.easeOut(duration: 0.12), value: rating)
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

import SwiftUI

// A single card in the activity feed showing what a friend did
struct ActivityCardView: View {
    let activity: FriendActivity

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            // User info row
            HStack(spacing: AppTheme.spacingSM) {
                ProfileImageView(systemName: activity.user.profileImageName, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(activity.user.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text(activity.activityLabel)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Text(activity.timeAgoString)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()
            }

            // Restaurant info
            HStack(spacing: AppTheme.spacingMD) {
                Image(systemName: activity.restaurant.imageName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(AppTheme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))

                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    Text(activity.restaurant.name)
                        .font(.headline)

                    HStack(spacing: AppTheme.spacingSM) {
                        Text(activity.restaurant.cuisineType)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)

                        if !activity.restaurant.priceLevelString.isEmpty {
                            Text("·")
                                .foregroundStyle(AppTheme.textSecondary)

                            Text(activity.restaurant.priceLevelString)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    // Show star rating if this is a review activity
                    if let review = activity.associatedReview {
                        StarRatingView(rating: review.clampedRating, starSize: 12)
                    }
                }

                Spacer()
            }

            // Review text (if present)
            if let review = activity.associatedReview, !review.text.isEmpty {
                Text(review.text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(3)
            }

            // Mood tags
            if let review = activity.associatedReview, !review.moodTags.isEmpty {
                MoodTagRow(tags: review.moodTags)
            }
        }
        .padding(AppTheme.spacingLG)
        .cardStyle()
    }
}

#Preview {
    // The mock's feed is built lazily, so reach for it directly rather than
    // through the now-async protocol method.
    let service = MockDataService()
    if let first = service.activityFeed.first {
        ActivityCardView(activity: first)
            .padding()
    }
}

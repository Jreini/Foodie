import SwiftUI

// A single card in the activity feed showing what a friend did.
//
// The card holds its links side by side rather than being one: the top row goes
// to the person, the restaurant rows go to the restaurant. They're siblings,
// not nested — a `NavigationLink` inside another one doesn't work.
//
// The photos sit between them for the same reason. They're buttons that open
// the viewer, and a button inside a link never sees its own tap — so the photo
// strip has to be a sibling too, which is what splits the restaurant summary
// into the part above the photos and the tags below them. It keeps the order a
// review has on the restaurant page: text, photos, tags.
struct ActivityCardView: View {
    let activity: FriendActivity

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            NavigationLink(value: activity.user) {
                userRow
            }
            .buttonStyle(.plain)

            NavigationLink(value: activity.restaurant) {
                restaurantSummary
            }
            .buttonStyle(.plain)

            if let review = activity.associatedReview {
                ReviewPhotoStrip(photoNames: review.photoNames)

                if !review.moodTags.isEmpty {
                    NavigationLink(value: activity.restaurant) {
                        MoodTagRow(tags: review.moodTags)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.spacingLG)
        .cardStyle()
    }

    private var userRow: some View {
        HStack(spacing: AppTheme.spacingSM) {
            ProfileImageView(user: activity.user, size: 36)

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
        .contentShape(Rectangle())
    }

    private var restaurantSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
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
        }
        // Without this the gaps between the rows aren't part of the link, and
        // the tap target has holes in it.
        .contentShape(Rectangle())
    }
}

#Preview {
    // The mock's feed is built lazily, so reach for it directly rather than
    // through the now-async protocol method.
    let service = MockDataService()
    NavigationStack {
        if let first = service.activityFeed.first {
            ActivityCardView(activity: first)
                .padding()
        }
    }
}

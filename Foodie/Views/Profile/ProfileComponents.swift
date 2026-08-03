import SwiftUI

// Pieces shared by your own profile and someone else's, so the two screens
// can't drift apart visually. Nothing here knows whose profile it is.

// One of the three counts under the avatar.
//
// It fills the width it's given on purpose: three stats sized to their own
// labels leave "Tasting List" much wider than "Reviews", which pushes the
// numbers off-centre even though the row itself is centred. Equal columns put
// each number in the middle of its third.
struct ProfileStat: View {
    // Nil for a count the viewer isn't allowed to know — a stranger's tasting
    // list, say. Showing 0 there would be a lie rather than a blank.
    let count: Int?
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(count.map { "\($0)" } ?? "—")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

// A review as it appears on a profile: the restaurant is the headline, since
// the person is already established by the screen.
struct ProfileReviewCard: View {
    let review: Review
    let restaurant: Restaurant

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                Text(restaurant.name)
                    .font(.headline)
                Spacer()
                StarRatingView(rating: review.clampedRating, starSize: 12)
            }

            Text(review.text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(2)

            if !review.moodTags.isEmpty {
                MoodTagRow(tags: review.moodTags)
            }

            Text(review.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacingLG)
        .cardStyle()
    }
}

// Stands in for an empty segment, and for one the viewer isn't allowed to see —
// `message` carries the difference.
struct ProfileSegmentPlaceholder: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.primaryColor.opacity(0.4))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingXL)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacingXXL)
    }
}

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 0) {
            ProfileStat(count: 12, label: "Reviews")
            ProfileStat(count: 3, label: "Friends")
            ProfileStat(count: 24, label: "Tasting List")
        }

        ProfileSegmentPlaceholder(
            icon: "lock",
            message: "Only friends can see this."
        )
    }
    .padding()
}

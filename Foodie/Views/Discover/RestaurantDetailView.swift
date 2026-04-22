import SwiftUI

struct RestaurantDetailView: View {
    let restaurant: Restaurant
    @State private var reviews: [Review] = []
    @State private var showWriteReview = false
    @State private var addedToTastingList = false

    private let dataService: DataServiceProtocol = MockDataService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImageSection
                infoSection
                tagsSection
                actionButtonsSection
                reviewsSection
            }
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reviews = dataService.fetchReviews(for: restaurant.id)
        }
        .sheet(isPresented: $showWriteReview) {
            WriteReviewSheet(restaurantName: restaurant.name)
        }
    }

    // MARK: - Sections

    private var heroImageSection: some View {
        ZStack(alignment: .bottomLeading) {
            Image(systemName: restaurant.imageName)
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(AppTheme.primaryGradient)

            // Overlay with restaurant name and cuisine
            VStack(alignment: .leading, spacing: 4) {
                Text(restaurant.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(restaurant.cuisineType)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(AppTheme.spacingLG)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            // Rating + price row
            HStack(spacing: AppTheme.spacingLG) {
                NumericRatingView(rating: restaurant.averageRating, starSize: 16)

                Text(restaurant.priceLevelString)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                // Open/closed indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(restaurant.isOpenNow ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(restaurant.isOpenNow ? "Open Now" : "Closed")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Divider()

            // Address
            Label(restaurant.address, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            // Hours
            Label(restaurant.hoursDescription, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.spacingLG)
    }

    private var tagsSection: some View {
        Group {
            if !restaurant.tags.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                    Text("Vibe")
                        .font(.headline)

                    MoodTagRow(tags: restaurant.tags)
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingMD)
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: AppTheme.spacingMD) {
            // Add to tasting list button
            Button {
                withAnimation { addedToTastingList.toggle() }
            } label: {
                Label(
                    addedToTastingList ? "On Tasting List" : "Tasting List",
                    systemImage: addedToTastingList ? "bookmark.fill" : "bookmark"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingMD)
                .background(addedToTastingList ? AppTheme.primaryColor : AppTheme.tagBackground)
                .foregroundStyle(addedToTastingList ? .white : AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
            }

            // Write a review button
            Button {
                showWriteReview = true
            } label: {
                Label("Review", systemImage: "square.and.pencil")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(AppTheme.primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
            }
        }
        .padding(.horizontal, AppTheme.spacingLG)
        .padding(.bottom, AppTheme.spacingMD)
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            Text("Reviews (\(reviews.count))")
                .font(.headline)
                .padding(.horizontal, AppTheme.spacingLG)

            if reviews.isEmpty {
                Text("No reviews yet. Be the first!")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, AppTheme.spacingLG)
            } else {
                ForEach(reviews) { review in
                    ReviewCard(review: review)
                }
            }
        }
        .padding(.bottom, AppTheme.spacingXL)
    }
}

// MARK: - Review Card (shown in restaurant detail)

private struct ReviewCard: View {
    let review: Review
    private let dataService: DataServiceProtocol = MockDataService()

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                // Reviewer info
                if let user = dataService.fetchAllUsers().first(where: { $0.id == review.userId }) {
                    ProfileImageView(systemName: user.profileImageName, size: 28)
                    Text(user.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Spacer()
                StarRatingView(rating: review.clampedRating, starSize: 11)
            }

            Text(review.text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

            if !review.moodTags.isEmpty {
                MoodTagRow(tags: review.moodTags)
            }

            Text(review.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.spacingLG)
        .cardStyle()
        .padding(.horizontal, AppTheme.spacingLG)
    }
}

// MARK: - Write Review Sheet (placeholder form)

private struct WriteReviewSheet: View {
    let restaurantName: String
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 3
    @State private var reviewText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    StarRatingView(rating: rating, starSize: 28)
                        .onTapGesture { location in
                            // Simple tap-based rating (approximate)
                            let tappedStar = Int(location.x / 32) + 1
                            rating = min(max(tappedStar, 1), 5)
                        }

                    // Manual stepper as backup
                    Stepper("Stars: \(rating)", value: $rating, in: 1...5)
                }

                Section("Your Review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Review \(restaurantName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(reviewText.isEmpty)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RestaurantDetailView(restaurant: Restaurant(
            id: MockDataService.restaurant1Id, name: "Sakura Sushi", cuisineType: "Japanese",
            address: "123 Cherry Blossom Ln", latitude: 0, longitude: 0,
            averageRating: 4.5, priceLevel: 3, imageName: "fork.knife.circle.fill",
            hoursDescription: "11 AM – 10 PM", tags: ["date night", "fresh fish", "sake bar"],
            isOpenNow: true
        ))
    }
}

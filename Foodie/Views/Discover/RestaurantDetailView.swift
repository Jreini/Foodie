import SwiftUI

struct RestaurantDetailView: View {
    let restaurant: Restaurant

    @State private var reviews: [Review] = []
    @State private var reviewersById: [UUID: User] = [:]
    @State private var showWriteReview = false
    @State private var isOnTastingList = false
    @State private var errorMessage: String?

    private let dataService: any DataServiceProtocol = DataServices.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroImageSection
                infoSection
                tagsSection
                actionButtonsSection
                errorBanner
                reviewsSection
            }
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showWriteReview) {
            WriteReviewSheet(
                restaurant: restaurant,
                existingReviewCount: reviews.count,
                onPosted: { await load() }
            )
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingSM)
        }
    }

    private func load() async {
        do {
            async let reviewsTask = dataService.fetchReviews(for: restaurant.id)
            async let usersTask = dataService.fetchAllUsers()
            async let currentUserTask = dataService.fetchCurrentUser()

            reviews = try await reviewsTask
            reviewersById = Dictionary(
                uniqueKeysWithValues: try await usersTask.map { ($0.id, $0) }
            )

            let currentUser = try await currentUserTask
            let tastingList = try await dataService.fetchTastingList(for: currentUser.id)
            isOnTastingList = tastingList.contains { $0.restaurantId == restaurant.id }
            errorMessage = nil
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // Flips the button immediately and syncs behind it, because waiting on a
    // round trip to shade a bookmark feels broken. A failure puts it back
    // rather than leaving the UI claiming something that didn't happen.
    private func toggleTastingList() async {
        let wasOnList = isOnTastingList
        withAnimation { isOnTastingList.toggle() }

        do {
            if wasOnList {
                try await dataService.removeFromTastingList(restaurantId: restaurant.id)
            } else {
                try await dataService.addToTastingList(restaurantId: restaurant.id, notes: "")
            }
            errorMessage = nil
        } catch {
            withAnimation { isOnTastingList = wasOnList }
            errorMessage = DataLoadFailure.message(for: error)
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

            // Tier badge row — contextualizes what the rating means
            HStack(spacing: AppTheme.spacingSM) {
                TierBadgeView(tier: restaurant.averageTier)
                Text(restaurant.averageTier.descriptiveLabel)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
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
                Task { await toggleTastingList() }
            } label: {
                Label(
                    isOnTastingList ? "On Tasting List" : "Tasting List",
                    systemImage: isOnTastingList ? "bookmark.fill" : "bookmark"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingMD)
                .background(isOnTastingList ? AppTheme.primaryColor : AppTheme.tagBackground)
                .foregroundStyle(isOnTastingList ? .white : AppTheme.textPrimary)
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
                    ReviewCard(review: review, reviewer: reviewersById[review.userId])
                }
            }
        }
        .padding(.bottom, AppTheme.spacingXL)
    }
}

// MARK: - Review Card (shown in restaurant detail)

private struct ReviewCard: View {
    let review: Review
    // Resolved by the parent, which already loads people in bulk — a card that
    // fetched its own author would issue one request per row.
    let reviewer: User?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack {
                // Reviewer info
                if let reviewer {
                    ProfileImageView(systemName: reviewer.profileImageName, size: 28)
                    Text(reviewer.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Spacer()
                // Tier badge + stars together show the rating in context
                TierBadgeView(tier: review.tierPlacement, style: .subtle)
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
    let restaurant: Restaurant
    // Passed in rather than re-fetched, so the flagging check doesn't need a
    // network round trip from inside a button handler.
    let existingReviewCount: Int
    let onPosted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 3
    @State private var reviewText: String = ""
    @State private var isPosting = false
    @State private var postError: String?
    // Initialize the tier placement at the restaurant's current crowd average
    // so the user starts near the consensus and nudges away if they disagree.
    @State private var tier: RestaurantTier
    @State private var showFlagConfirmation = false
    @State private var pendingFlagMessage: String = ""

    private let dataService: any DataServiceProtocol = DataServices.current

    init(
        restaurant: Restaurant,
        existingReviewCount: Int,
        onPosted: @escaping () async -> Void
    ) {
        self.restaurant = restaurant
        self.existingReviewCount = existingReviewCount
        self.onPosted = onPosted
        _tier = State(initialValue: restaurant.averageTier)
    }

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

                Section {
                    TierSliderView(
                        tier: $tier,
                        averageTier: restaurant.averageTier
                    )
                    .padding(.vertical, AppTheme.spacingXS)
                } header: {
                    Text("Tier Placement")
                } footer: {
                    // Help users understand what the slider is for
                    Text("Where does this restaurant sit on the spectrum? A " +
                         "5-star fast-food spot and a 5-star fine-dining spot " +
                         "aren't the same thing.")
                }

                Section("Your Review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 100)
                }

                if let postError {
                    Section {
                        Text(postError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Review \(restaurant.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post") { attemptPost() }
                            .fontWeight(.semibold)
                            .disabled(reviewText.isEmpty)
                    }
                }
            }
            .alert(
                "Does this look right?",
                isPresented: $showFlagConfirmation,
                actions: {
                    // User confirms — post anyway with their original placement
                    Button("Yes, post it", role: .destructive) {
                        Task { await post() }
                    }
                    // User backs out to adjust the slider
                    Button("Let me adjust", role: .cancel) { }
                },
                message: { Text(pendingFlagMessage) }
            )
        }
    }

    // Evaluate the placement and either show the confirmation alert or post
    private func attemptPost() {
        let result = TierFlaggingService.evaluate(
            placement: tier,
            averageTier: restaurant.averageTier,
            restaurantName: restaurant.name,
            existingReviewCount: existingReviewCount
        )
        if result.shouldFlag {
            pendingFlagMessage = result.suggestedMessage
            showFlagConfirmation = true
        } else {
            Task { await post() }
        }
    }

    private func post() async {
        isPosting = true
        postError = nil
        defer { isPosting = false }

        do {
            try await dataService.submitReview(
                restaurantId: restaurant.id,
                rating: rating,
                text: reviewText,
                // Mood tags don't have an input control yet; the column and the
                // model field are both ready for when one lands.
                moodTags: [],
                tierPlacement: tier
            )
            await onPosted()
            dismiss()
        } catch {
            postError = DataLoadFailure.message(for: error)
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
            isOpenNow: true,
            baselineTier: RestaurantTier(0.72),
            averageTier: RestaurantTier(0.72)
        ))
    }
}

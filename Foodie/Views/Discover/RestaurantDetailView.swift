import SwiftUI
import PhotosUI

struct RestaurantDetailView: View {
    let restaurant: Restaurant

    @State private var reviews: [Review] = []
    @State private var reviewersById: [UUID: User] = [:]
    @State private var showWriteReview = false
    @State private var isOnTastingList = false
    @State private var isLiked = false
    @State private var errorMessage: String?

    // The database row for this place, once we know there is one. A MapKit
    // search result doesn't have one until somebody interacts with it.
    @State private var persistedRow: Restaurant?

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
                resolveRestaurantId: { try await persistedRowId() },
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

    // Merely looking at a place doesn't create a row for it — that would fill
    // the table with everywhere anyone ever scrolled past. So this resolves an
    // existing row if there is one and otherwise shows an empty state.
    private func existingRowId() async -> UUID? {
        if let persistedRow { return persistedRow.id }
        if restaurant.isPersisted { return restaurant.id }

        guard let placeId = restaurant.mapkitPlaceId,
              let row = try? await dataService.fetchRestaurants(mapkitPlaceIds: [placeId]).first
        else { return nil }

        persistedRow = row
        return row.id
    }

    // Called before any write. This is the moment a MapKit result becomes a
    // real row.
    private func persistedRowId() async throws -> UUID {
        if let existing = await existingRowId() { return existing }

        let row = try await dataService.ensureRestaurantPersisted(restaurant)
        persistedRow = row
        return row.id
    }

    private func load() async {
        do {
            async let usersTask = dataService.fetchAllUsers()
            async let currentUserTask = dataService.fetchCurrentUser()

            reviewersById = Dictionary(
                uniqueKeysWithValues: try await usersTask.map { ($0.id, $0) }
            )
            let currentUser = try await currentUserTask

            guard let rowId = await existingRowId() else {
                // Nobody has interacted with this place yet, so there's nothing
                // to load — not an error.
                reviews = []
                isOnTastingList = false
                isLiked = false
                errorMessage = nil
                return
            }

            async let reviewsTask = dataService.fetchReviews(for: rowId)
            async let tastingTask = dataService.fetchTastingList(for: currentUser.id)
            async let likedTask = dataService.fetchLikedRestaurantIds(for: currentUser.id)

            reviews = try await reviewsTask
            isOnTastingList = try await tastingTask.contains { $0.restaurantId == rowId }
            isLiked = try await likedTask.contains(rowId)
            errorMessage = nil
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // Liking is the lightest way to say "I'd go here", and it's what feeds the
    // group pick — so like the tasting list, it persists the place first.
    private func toggleLike() async {
        let wasLiked = isLiked
        withAnimation { isLiked.toggle() }

        do {
            let rowId = try await persistedRowId()
            try await dataService.setLiked(!wasLiked, restaurantId: rowId)
            errorMessage = nil
        } catch {
            withAnimation { isLiked = wasLiked }
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
            let rowId = try await persistedRowId()
            if wasOnList {
                try await dataService.removeFromTastingList(restaurantId: rowId)
            } else {
                try await dataService.addToTastingList(restaurantId: rowId, notes: "")
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

                // Open/closed indicator, shown only when hours are actually
                // known. MapKit doesn't report them.
                if let isOpenNow = restaurant.isOpenNow {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isOpenNow ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(isOpenNow ? "Open Now" : "Closed")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
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

            // Hours, when we have them
            if let hours = restaurant.hoursDescription, !hours.isEmpty {
                Label(hours, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
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
            // Like — icon only, so the two wordier actions keep their room.
            Button {
                Task { await toggleLike() }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 52)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(isLiked ? Color.pink : AppTheme.tagBackground)
                    .foregroundStyle(isLiked ? .white : AppTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
            }
            .accessibilityLabel(isLiked ? "Unlike" : "Like")

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
                // Three buttons in one row is tight on a small iPhone; shrink
                // the text rather than truncating "On Tasting List".
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
                // Reviewer info, linked to their profile — a review is the most
                // common place you meet someone you haven't added yet.
                if let reviewer {
                    NavigationLink(value: reviewer) {
                        HStack(spacing: AppTheme.spacingSM) {
                            ProfileImageView(user: reviewer, size: 28)
                            Text(reviewer.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                // Tier badge + stars together show the rating in context
                TierBadgeView(tier: review.tierPlacement, style: .subtle)
                StarRatingView(rating: review.clampedRating, starSize: 11)
            }

            Text(review.text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)

            if !review.photoNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        ForEach(review.photoNames, id: \.self) { path in
                            reviewPhoto(path)
                        }
                    }
                }
            }

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

    // Mock reviews carry SF Symbol names rather than storage paths, so fall
    // back to a symbol when the path doesn't resolve to a URL.
    @ViewBuilder
    private func reviewPhoto(_ path: String) -> some View {
        if let url = PhotoUploadService.publicURL(for: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(AppTheme.textSecondary)
                default:
                    ProgressView()
                }
            }
            .frame(width: 120, height: 120)
            .background(AppTheme.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
        }
    }
}

// MARK: - Write Review Sheet (placeholder form)

private struct WriteReviewSheet: View {
    let restaurant: Restaurant
    // Passed in rather than re-fetched, so the flagging check doesn't need a
    // network round trip from inside a button handler.
    let existingReviewCount: Int
    // Creates the database row if this place is still only a MapKit result,
    // and hands back the id to attach the review to.
    let resolveRestaurantId: () async throws -> UUID
    let onPosted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 3
    @State private var reviewText: String = ""
    @State private var isPosting = false
    @State private var postError: String?
    @State private var pickerSelections: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var isLoadingPhotos = false

    // A multi-line TextEditor has no return key to dismiss with — Return
    // inserts a newline — so the keyboard needs an explicit way out.
    @FocusState private var isReviewFieldFocused: Bool
    // Initialize the tier placement at the restaurant's current crowd average
    // so the user starts near the consensus and nudges away if they disagree.
    @State private var tier: RestaurantTier
    @State private var showFlagConfirmation = false
    @State private var pendingFlagMessage: String = ""

    private let dataService: any DataServiceProtocol = DataServices.current

    init(
        restaurant: Restaurant,
        existingReviewCount: Int,
        resolveRestaurantId: @escaping () async throws -> UUID,
        onPosted: @escaping () async -> Void
    ) {
        self.restaurant = restaurant
        self.existingReviewCount = existingReviewCount
        self.resolveRestaurantId = resolveRestaurantId
        self.onPosted = onPosted
        _tier = State(initialValue: restaurant.averageTier)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    // The stepper that used to sit here was a workaround for
                    // the broken tap handling; the stars are directly tappable
                    // now, so it's just clutter.
                    StarRatingInput(rating: $rating, starSize: 28)
                        .frame(maxWidth: .infinity, alignment: .center)
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
                        .focused($isReviewFieldFocused)
                }

                Section {
                    photoStrip

                    PhotosPicker(
                        selection: $pickerSelections,
                        maxSelectionCount: 4,
                        matching: .images
                    ) {
                        Label(
                            photos.isEmpty ? "Add Photos" : "Change Photos",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                } header: {
                    Text("Photos")
                } footer: {
                    Text("Photos are shrunk on your device before upload.")
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isReviewFieldFocused = false }
                        .fontWeight(.semibold)
                }
            }
            // Swiping the form down also dismisses, so reaching for the button
            // isn't the only way out.
            .scrollDismissesKeyboard(.interactively)
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
            .onChange(of: pickerSelections) { _, items in
                Task { await loadPickedPhotos(items) }
            }
        }
    }

    @ViewBuilder
    private var photoStrip: some View {
        if isLoadingPhotos {
            HStack {
                ProgressView()
                Text("Loading photos…").foregroundStyle(AppTheme.textSecondary)
            }
        } else if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSM) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
                    }
                }
                .padding(.vertical, AppTheme.spacingXS)
            }
        }
    }

    // PhotosPickerItem only hands over data on request, so decode after the
    // picker closes rather than blocking it.
    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            photos = []
            return
        }

        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        photos = loaded
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
            let restaurantId = try await resolveRestaurantId()

            // Photos go up first: a review row referencing an upload that
            // failed would render as broken images forever.
            let photoPaths = try await uploadPhotos()

            try await dataService.submitReview(
                restaurantId: restaurantId,
                rating: rating,
                text: reviewText,
                // Mood tags don't have an input control yet; the column and the
                // model field are both ready for when one lands.
                moodTags: [],
                photoPaths: photoPaths,
                tierPlacement: tier
            )
            await onPosted()
            dismiss()
        } catch {
            postError = DataLoadFailure.message(for: error)
        }
    }

    private func uploadPhotos() async throws -> [String] {
        guard !photos.isEmpty else { return [] }

        let currentUser = try await dataService.fetchCurrentUser()
        var paths: [String] = []
        for photo in photos {
            paths.append(try await PhotoUploadService.upload(photo, userId: currentUser.id))
        }
        return paths
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

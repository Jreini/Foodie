import SwiftUI

struct ProfileView: View {
    @State private var viewModel = ProfileViewModel()
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingLG) {
                    profileHeader
                    segmentedPicker
                    segmentContent
                }
                .padding(.bottom, AppTheme.spacingXL)
            }
            .background(AppTheme.screenBackground)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditProfile = true
                    } label: {
                        Text("Edit")
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                if let user = viewModel.currentUser {
                    EditProfileView(user: user)
                }
            }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .onAppear { viewModel.loadProfile() }
        }
    }

    // MARK: - Subviews

    private var profileHeader: some View {
        VStack(spacing: AppTheme.spacingMD) {
            // Profile image
            ProfileImageView(
                systemName: viewModel.currentUser?.profileImageName ?? "person.circle.fill",
                size: 80
            )

            // Name and username
            VStack(spacing: AppTheme.spacingXS) {
                Text(viewModel.currentUser?.name ?? "")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("@\(viewModel.currentUser?.username ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // Bio
            if let bio = viewModel.currentUser?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingXXL)
            }

            // Stats row
            HStack(spacing: AppTheme.spacingXXL) {
                profileStat(count: viewModel.reviewCount, label: "Reviews")
                profileStat(count: viewModel.friendCount, label: "Friends")
                profileStat(count: viewModel.tastingListCount, label: "Tasting List")
            }
            .padding(.top, AppTheme.spacingSM)
        }
        .padding(.top, AppTheme.spacingMD)
    }

    private func profileStat(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var segmentedPicker: some View {
        Picker("Section", selection: $viewModel.selectedSegment) {
            ForEach(ProfileViewModel.ProfileSegment.allCases, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.spacingLG)
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch viewModel.selectedSegment {
        case .reviews:
            reviewsList
        case .liked:
            likedList
        case .tastingList:
            tastingList
        }
    }

    private var reviewsList: some View {
        LazyVStack(spacing: AppTheme.spacingMD) {
            if viewModel.userReviews.isEmpty {
                emptySegmentView(icon: "square.and.pencil", message: "No reviews yet")
            } else {
                ForEach(viewModel.userReviews) { review in
                    if let restaurant = viewModel.restaurantForReview(review) {
                        NavigationLink(value: restaurant) {
                            userReviewCard(review: review, restaurant: restaurant)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.spacingLG)
    }

    private func userReviewCard(review: Review, restaurant: Restaurant) -> some View {
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
        .padding(AppTheme.spacingLG)
        .cardStyle()
    }

    private var likedList: some View {
        LazyVStack(spacing: AppTheme.spacingSM) {
            if viewModel.likedRestaurants.isEmpty {
                emptySegmentView(icon: "heart", message: "No liked restaurants")
            } else {
                ForEach(viewModel.likedRestaurants) { restaurant in
                    NavigationLink(value: restaurant) {
                        RestaurantRowView(restaurant: restaurant)
                            .padding(.horizontal, AppTheme.spacingLG)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tastingList: some View {
        LazyVStack(spacing: AppTheme.spacingSM) {
            if viewModel.tastingListRestaurants.isEmpty {
                emptySegmentView(icon: "bookmark", message: "Tasting list is empty")
            } else {
                ForEach(viewModel.tastingListRestaurants) { restaurant in
                    NavigationLink(value: restaurant) {
                        RestaurantRowView(restaurant: restaurant)
                            .padding(.horizontal, AppTheme.spacingLG)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptySegmentView(icon: String, message: String) -> some View {
        VStack(spacing: AppTheme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.primaryColor.opacity(0.4))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacingXXL)
    }
}

#Preview {
    ProfileView()
}

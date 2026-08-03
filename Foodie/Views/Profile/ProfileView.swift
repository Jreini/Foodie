import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var viewModel = ProfileViewModel()
    @State private var showEditProfile = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

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
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        // The header names the signed-in account. Until the
                        // profiles table lands in Phase 2 the rest of this
                        // screen is still mock data, so this is the only place
                        // that reflects who is actually logged in.
                        Section(accountLabel) {
                            Button(role: .destructive) {
                                showSignOutConfirmation = true
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }

                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete Account", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditProfile = true
                    } label: {
                        Text("Edit")
                    }
                }
            }
            .confirmationDialog(
                "Sign out of Foodie?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your profile, reviews, photos, lists, and friends. It can't be undone.")
            }
            .alert("Couldn't delete account", isPresented: .constant(deleteError != nil)) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("Deleting…")
                            .padding(AppTheme.spacingXL)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLG))
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                if let profile = auth.profile {
                    EditProfileView(profile: profile)
                }
            }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .refreshable { await viewModel.loadProfile() }
            .task { await viewModel.loadProfile() }
        }
    }

    // The service signs out after a successful delete, which flips AuthManager
    // to .signedOut and swaps this whole screen for the login view.
    private func deleteAccount() async {
        isDeletingAccount = true
        deleteError = nil
        defer { isDeletingAccount = false }

        do {
            try await DataServices.current.deleteAccount()
        } catch {
            deleteError = DataLoadFailure.message(for: error)
        }
    }

    // Name shown in the account menu, falling back to the sign-in email.
    private var accountLabel: String {
        guard case .ready(let user, let profile) = auth.state else { return "Account" }
        return profile.username.map { "@\($0)" } ?? user.email ?? "Account"
    }

    // MARK: - Subviews

    private var profileHeader: some View {
        VStack(spacing: AppTheme.spacingMD) {
            // Profile image
            ProfileImageView(
                systemName: viewModel.currentUser?.profileImageName ?? "person.circle.fill",
                size: 80
            )

            // Name and username come from the real profile row. The stats below
            // are still mock — they move to Supabase in Phase 3.
            VStack(spacing: AppTheme.spacingXS) {
                Text(auth.profile?.displayName ?? "")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(auth.profile?.usernameHandle ?? "")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            // Bio
            if let bio = auth.profile?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingXXL)
            }

            // Stats row. Friends is the only one that leads somewhere, since
            // it's where requests are answered.
            HStack(spacing: AppTheme.spacingXXL) {
                profileStat(count: viewModel.reviewCount, label: "Reviews")

                NavigationLink {
                    FriendsView()
                } label: {
                    profileStat(count: viewModel.friendCount, label: "Friends")
                }
                .buttonStyle(.plain)

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
        .environment(AuthManager())
}

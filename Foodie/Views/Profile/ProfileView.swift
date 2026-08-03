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
                        // Titled with the account, so the two irreversible
                        // actions underneath are unmistakably about *this*
                        // sign-in and not the profile being viewed.
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
            .personProfileDestination()
            .friendsListDestination()
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
            ProfileImageView(avatarPath: auth.profile?.avatarPath, size: 80)

            VStack(spacing: AppTheme.spacingXS) {
                Text(auth.profile?.displayName ?? "")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

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

            statsRow
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.spacingMD)
    }

    // Three equal columns rather than three self-sized ones. Sized to their own
    // labels, "Tasting List" is half again as wide as "Reviews", which drags
    // the numbers off-centre even though the row is centred as a whole — which
    // is exactly what looked crooked.
    private var statsRow: some View {
        HStack(spacing: 0) {
            ProfileStat(count: viewModel.reviewCount, label: "Reviews")

            // Friends is the only stat that leads somewhere, since it's where
            // requests are answered.
            NavigationLink(value: FriendsRoute()) {
                ProfileStat(count: viewModel.friendCount, label: "Friends")
            }
            .buttonStyle(.plain)

            ProfileStat(count: viewModel.tastingListCount, label: "Tasting List")
        }
        .padding(.horizontal, AppTheme.spacingXL)
        .padding(.top, AppTheme.spacingSM)
    }

    private var segmentedPicker: some View {
        Picker("Section", selection: $viewModel.selectedSegment) {
            ForEach(ProfileSegment.allCases, id: \.self) { segment in
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
                ProfileSegmentPlaceholder(icon: "square.and.pencil", message: "No reviews yet")
            } else {
                ForEach(viewModel.userReviews) { review in
                    if let restaurant = viewModel.restaurantForReview(review) {
                        NavigationLink(value: restaurant) {
                            ProfileReviewCard(review: review, restaurant: restaurant)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.spacingLG)
    }

    private var likedList: some View {
        LazyVStack(spacing: AppTheme.spacingSM) {
            if viewModel.likedRestaurants.isEmpty {
                ProfileSegmentPlaceholder(icon: "heart", message: "No liked restaurants")
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
                ProfileSegmentPlaceholder(icon: "bookmark", message: "Tasting list is empty")
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

}

#Preview {
    ProfileView()
        .environment(AuthManager())
}

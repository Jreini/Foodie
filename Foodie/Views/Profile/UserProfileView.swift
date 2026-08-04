import SwiftUI

// Somebody else's profile, reached by tapping their name anywhere they appear.
//
// Mirrors your own profile — same header, same three segments — except that
// what a viewer may see depends on the friendship. Reviews are public within
// the app; liked restaurants and tasting lists are friends-only, enforced by
// RLS and *reported* here rather than decided here.
struct UserProfileView: View {
    @State private var viewModel: UserProfileViewModel

    init(user: User) {
        _viewModel = State(initialValue: UserProfileViewModel(user: user))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacingLG) {
                profileHeader
                friendshipAction
                segmentedPicker
                segmentContent
            }
            .padding(.bottom, AppTheme.spacingXL)
        }
        .background(AppTheme.screenBackground)
        .navigationTitle(viewModel.user.username.isEmpty ? viewModel.user.name : "@\(viewModel.user.username)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { loadingOverlay }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: AppTheme.spacingMD) {
            ProfileImageView(user: viewModel.user, size: 80, opensFullScreen: true)

            VStack(spacing: AppTheme.spacingXS) {
                Text(viewModel.user.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if !viewModel.user.username.isEmpty {
                    Text("@\(viewModel.user.username)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            if !viewModel.user.bio.isEmpty {
                Text(viewModel.user.bio)
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

    private var statsRow: some View {
        HStack(spacing: 0) {
            ProfileStat(count: viewModel.reviewCount, label: "Reviews")
            ProfileStat(count: viewModel.friendCount, label: "Friends")
            ProfileStat(count: viewModel.visibleTastingListCount, label: "Tasting List")
        }
        .padding(.horizontal, AppTheme.spacingXL)
        .padding(.top, AppTheme.spacingSM)
    }

    // MARK: - Friendship

    @ViewBuilder
    private var friendshipAction: some View {
        VStack(spacing: AppTheme.spacingSM) {
            switch viewModel.friendshipState {
            case .currentUser:
                EmptyView()

            case .none:
                Button {
                    Task { await viewModel.sendRequest() }
                } label: {
                    Label("Add Friend", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryColor)

            case .requestSent:
                // Matches the friends list, which also shows a sent request as
                // a state rather than something to tap.
                Label("Request Sent", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)

            case .requestReceived:
                Button {
                    Task { await viewModel.acceptRequest() }
                } label: {
                    Label("Accept Request", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryColor)

            case .friends:
                // A menu rather than a bare button: unfriending shouldn't be
                // one accidental tap away from a row you meant to read.
                Menu {
                    Button("Remove Friend", role: .destructive) {
                        Task { await viewModel.removeFriend() }
                    }
                } label: {
                    Label("Friends", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primaryColor)
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .disabled(viewModel.isUpdatingFriendship)
        .padding(.horizontal, AppTheme.spacingLG)
    }

    // MARK: - Segments

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
            savedList(
                restaurants: viewModel.likedRestaurants,
                emptyIcon: "heart",
                emptyMessage: "No liked restaurants yet"
            )
        case .tastingList:
            savedList(
                restaurants: viewModel.tastingListRestaurants,
                emptyIcon: "bookmark",
                emptyMessage: "Nothing on their tasting list yet"
            )
        }
    }

    private var reviewsList: some View {
        LazyVStack(spacing: AppTheme.spacingMD) {
            if viewModel.reviews.isEmpty {
                ProfileSegmentPlaceholder(
                    icon: "square.and.pencil",
                    message: "No reviews yet"
                )
            } else {
                ForEach(viewModel.reviews) { review in
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

    @ViewBuilder
    private func savedList(
        restaurants: [Restaurant],
        emptyIcon: String,
        emptyMessage: String
    ) -> some View {
        if !viewModel.canSeeSavedRestaurants {
            ProfileSegmentPlaceholder(
                icon: "lock",
                message: "\(viewModel.user.name) shares this with friends only."
            )
        } else {
            LazyVStack(spacing: AppTheme.spacingSM) {
                if restaurants.isEmpty {
                    ProfileSegmentPlaceholder(icon: emptyIcon, message: emptyMessage)
                } else {
                    ForEach(restaurants) { restaurant in
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

    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.isLoading && !viewModel.hasLoadedOnce {
            ProgressView()
        }
    }
}

// MARK: - Navigation

extension View {
    // Registers `User` as a pushable value, so anywhere a person appears can be
    // a plain `NavigationLink(value:)` without knowing what a profile looks like.
    //
    // Apply this once per `NavigationStack`, at its root, alongside the
    // `Restaurant` destination — SwiftUI keeps only one destination per type per
    // stack, and declaring it deeper as well makes which one wins depend on
    // where the user happens to be.
    func personProfileDestination() -> some View {
        navigationDestination(for: User.self) { user in
            UserProfileView(user: user)
        }
    }
}

#Preview {
    NavigationStack {
        UserProfileView(
            user: User(
                id: MockDataService.friend1Id,
                name: "Mia Chen",
                username: "miabites",
                avatarPath: nil,
                bio: "Sushi snob & coffee addict.",
                joinDate: Date(),
                friendIds: []
            )
        )
    }
}

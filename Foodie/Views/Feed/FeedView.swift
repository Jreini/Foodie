import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @Environment(PushRouter.self) private var router

    // Bound rather than implicit, because a tapped notification has to be able
    // to push a screen this view didn't choose.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: AppTheme.spacingMD) {
                    ForEach(viewModel.activities) { activity in
                        // The card owns its own links now — one for the person,
                        // one for the restaurant — so it can't be wrapped in a
                        // third. Nested navigation links don't work.
                        ActivityCardView(activity: activity)
                            .task { await viewModel.loadMoreIfNeeded(currentItem: activity) }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView().padding(.vertical, AppTheme.spacingLG)
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.top, AppTheme.spacingSM)
            }
            .background(AppTheme.screenBackground)
            .navigationTitle("Feed")
            .toolbar {
                // Left of Friends, because it's the broader inbox: everything
                // that shows up here is a thing that happened to you, and
                // friend requests are only one kind.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: NotificationsRoute()) {
                        Image(systemName: "bell")
                            .overlay(alignment: .topTrailing) {
                                if viewModel.unreadNotificationCount > 0 {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 5, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel(
                        viewModel.unreadNotificationCount > 0
                            ? "Notifications, \(viewModel.unreadNotificationCount) unread"
                            : "Notifications"
                    )
                }

                // The feed is the screen people actually open, so friends live
                // here as well as behind the count on Profile — that's where
                // requests are answered, and an unanswered one is why the feed
                // is empty in the first place.
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: FriendsRoute()) {
                        Image(systemName: "person.2.fill")
                            .overlay(alignment: .topTrailing) {
                                // A dot rather than a count: the number doesn't
                                // change what you do about it, and `.badge()`
                                // only means something on list rows and tabs.
                                if viewModel.pendingRequestCount > 0 {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 5, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel(
                        viewModel.pendingRequestCount > 0
                            ? "Friends, \(viewModel.pendingRequestCount) pending requests"
                            : "Friends"
                    )
                }
            }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .personProfileDestination()
            .friendsListDestination()
            .notificationsDestination()
            .refreshable { await viewModel.loadActivityFeed() }
            .overlay { statusOverlay }
            .task { await viewModel.loadActivityFeed() }
            // Both hooks, for the reason given in `MainTabView`: `onAppear`
            // catches a route that was already pending when this tab was
            // selected, `onChange` catches one that arrives while it's showing.
            .onAppear {
                consumePendingRoute()
                // Coming back from the inbox or the Friends screen: both badges
                // may have just been answered. `.task` above only fires once.
                Task { await viewModel.refreshBadges() }
            }
            .onChange(of: router.destination) { consumePendingRoute() }
        }
    }

    // Only claims routes this stack can actually show, so a Shared Lists route
    // stays pending for the Decide tab instead of being swallowed here.
    private func consumePendingRoute() {
        guard router.consume(.friends) else { return }
        path.append(FriendsRoute())
    }

    // Covers the three states a list can be in besides "has content".
    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.activities.isEmpty {
            ProgressView()
        } else if let message = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Couldn't load your feed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.loadActivityFeed() }
                }
            }
        } else if viewModel.hasLoadedOnce && viewModel.activities.isEmpty {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "fork.knife")
            } description: {
                Text("Reviews and check-ins from you and your friends show up here.")
            } actions: {
                NavigationLink(value: FriendsRoute()) {
                    Text("Find Friends")
                }
            }
        }
    }
}

#Preview {
    FeedView()
        .environment(PushRouter.shared)
}

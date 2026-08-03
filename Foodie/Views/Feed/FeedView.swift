import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        NavigationStack {
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
                // The feed is the screen people actually open, so friends live
                // here as well as behind the count on Profile — that's where
                // requests are answered, and an unanswered one is why the feed
                // is empty in the first place.
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        FriendsView()
                    } label: {
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
            .refreshable { await viewModel.loadActivityFeed() }
            .overlay { statusOverlay }
            .task { await viewModel.loadActivityFeed() }
        }
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
                NavigationLink {
                    FriendsView()
                } label: {
                    Text("Find Friends")
                }
            }
        }
    }
}

#Preview {
    FeedView()
}

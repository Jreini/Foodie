import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppTheme.spacingMD) {
                    ForEach(viewModel.activities) { activity in
                        NavigationLink(value: activity.restaurant) {
                            ActivityCardView(activity: activity)
                        }
                        .buttonStyle(.plain)
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
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
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
            }
        }
    }
}

#Preview {
    FeedView()
}

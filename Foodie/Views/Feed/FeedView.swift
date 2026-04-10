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
            .onAppear {
                viewModel.loadActivityFeed()
            }
        }
    }
}

#Preview {
    FeedView()
}

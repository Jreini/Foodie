import SwiftUI

struct DiscoverView: View {
    @State private var viewModel = DiscoverViewModel()

    // Two-column grid for restaurant cards
    private let gridColumns = [
        GridItem(.flexible(), spacing: AppTheme.spacingMD),
        GridItem(.flexible(), spacing: AppTheme.spacingMD),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                    cuisineCategoryPicker
                    restaurantGrid
                }
                .padding(.top, AppTheme.spacingSM)
            }
            .background(AppTheme.screenBackground)
            .navigationTitle("Discover")
            .searchable(text: $viewModel.searchText, prompt: "Search restaurants or cuisines")
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .refreshable { await viewModel.loadRestaurants() }
            .overlay { statusOverlay }
            .task { await viewModel.loadRestaurants() }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.allRestaurants.isEmpty {
            ProgressView()
        } else if let message = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Couldn't load restaurants", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.loadRestaurants() }
                }
            }
        } else if !viewModel.searchText.isEmpty && viewModel.filteredRestaurants.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        }
    }

    // MARK: - Subviews

    // Horizontal scrolling cuisine category chips
    private var cuisineCategoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingSM) {
                ForEach(viewModel.cuisineCategories, id: \.self) { cuisine in
                    Button {
                        viewModel.toggleCuisineFilter(cuisine)
                    } label: {
                        Text(cuisine)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, AppTheme.spacingMD)
                            .padding(.vertical, AppTheme.spacingSM)
                            .background(
                                viewModel.selectedCuisine == cuisine
                                    ? AppTheme.primaryColor
                                    : AppTheme.tagBackground
                            )
                            .foregroundStyle(
                                viewModel.selectedCuisine == cuisine
                                    ? .white
                                    : AppTheme.textPrimary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
    }

    // Grid layout of restaurant cards
    private var restaurantGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: AppTheme.spacingMD) {
            ForEach(viewModel.filteredRestaurants) { restaurant in
                NavigationLink(value: restaurant) {
                    RestaurantCardView(restaurant: restaurant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.spacingLG)
    }
}

#Preview {
    DiscoverView()
}

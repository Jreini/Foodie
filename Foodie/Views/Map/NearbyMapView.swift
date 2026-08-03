import SwiftUI
import MapKit

// Nearby restaurants on a real map.
//
// Shares `DiscoverViewModel` with the Discover tab: same MapKit search, same
// crowd-data merge, just plotted instead of listed. Tabs get their own
// instances, so the two don't fight over state.
struct NearbyMapView: View {
    @State private var viewModel = DiscoverViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRestaurant: Restaurant?

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition, selection: $selectedRestaurant) {
                UserAnnotation()

                ForEach(viewModel.filteredRestaurants) { restaurant in
                    Marker(
                        restaurant.name,
                        systemImage: "fork.knife",
                        coordinate: restaurant.coordinate
                    )
                    .tint(restaurant.averageTier.zone.accentColor)
                    .tag(restaurant)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search nearby")
            .overlay(alignment: .top) { statusBanner }
            .safeAreaInset(edge: .bottom) { selectionCard }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .task { await viewModel.loadNearby() }
        }
    }

    // MARK: - Status

    // Pins are colored by tier zone, which is only meaningful if you know that,
    // so the banner doubles as an explanation when something's off.
    @ViewBuilder
    private var statusBanner: some View {
        if viewModel.isLoading {
            banner(text: "Searching nearby…", systemImage: "location.magnifyingglass")
        } else if viewModel.isShowingSavedPlacesOnly {
            banner(
                text: "Location off — showing saved places",
                systemImage: "location.slash"
            )
        }
    }

    private func banner(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, AppTheme.spacingSM)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, AppTheme.spacingSM)
    }

    // MARK: - Selection

    // Tapping a pin surfaces enough to decide whether to open the full page.
    @ViewBuilder
    private var selectionCard: some View {
        if let selectedRestaurant {
            NavigationLink(value: selectedRestaurant) {
                HStack(spacing: AppTheme.spacingMD) {
                    VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                        Text(selectedRestaurant.name)
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)

                        HStack(spacing: AppTheme.spacingSM) {
                            Text(selectedRestaurant.cuisineType)
                            if !selectedRestaurant.priceLevelString.isEmpty {
                                Text("·")
                                Text(selectedRestaurant.priceLevelString)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                        TierBadgeView(tier: selectedRestaurant.averageTier, style: .subtle)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(AppTheme.spacingLG)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLG))
                .padding(AppTheme.spacingLG)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

#Preview {
    NearbyMapView()
}

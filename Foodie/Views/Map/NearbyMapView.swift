import SwiftUI
import MapKit
import CoreLocation

// Nearby restaurants on a real map.
//
// Shares `DiscoverViewModel` with the Discover tab: same MapKit search, same
// crowd-data merge, just plotted instead of listed. Tabs get their own
// instances, so the two don't fight over state.
struct NearbyMapView: View {
    @State private var viewModel = DiscoverViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRestaurant: Restaurant?

    // Centre of the visible map, updated as the user pans.
    @State private var visibleCenter: CLLocationCoordinate2D?

    // Far enough that re-searching would actually return different places.
    // Below this the results would be nearly identical, so the button would be
    // noise rather than an offer.
    private let researchThresholdMeters: CLLocationDistance = 1_200

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
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleCenter = context.region.center
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchText, prompt: "Search nearby")
            .overlay(alignment: .top) { statusBanner }
            .animation(.easeInOut(duration: 0.2), value: hasPannedAway)
            .safeAreaInset(edge: .bottom) { selectionCard }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .personProfileDestination()
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
        } else if hasPannedAway {
            searchThisAreaButton
        } else if viewModel.isShowingSavedPlacesOnly {
            banner(
                text: "Location off — showing saved places",
                systemImage: "location.slash"
            )
        }
    }

    // Only offered once the map has moved far enough that a fresh search would
    // return meaningfully different places.
    private var hasPannedAway: Bool {
        guard let visibleCenter, let searched = viewModel.lastSearchCenter else { return false }

        let from = CLLocation(latitude: searched.latitude, longitude: searched.longitude)
        let to = CLLocation(latitude: visibleCenter.latitude, longitude: visibleCenter.longitude)
        return from.distance(from: to) > researchThresholdMeters
    }

    private var searchThisAreaButton: some View {
        Button {
            Task { await viewModel.loadNearby(at: visibleCenter) }
        } label: {
            Label("Search this area", systemImage: "arrow.trianglehead.clockwise")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.vertical, AppTheme.spacingMD)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, AppTheme.spacingSM)
        .transition(.move(edge: .top).combined(with: .opacity))
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

import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
class DiscoverViewModel {
    var allRestaurants: [Restaurant] = []
    var filteredRestaurants: [Restaurant] = []
    var isLoading = false
    var errorMessage: String?
    var hasLoadedOnce = false

    // True when we couldn't get a location and fell back to whatever the
    // database already knows about, so the UI can say why the list looks odd.
    var isShowingSavedPlacesOnly = false

    // Search now goes to MapKit rather than filtering a local array, so it's
    // debounced — one network search per pause in typing, not per keystroke.
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    var selectedCuisine: String? = nil {
        didSet { applyFilters() }
    }

    var cuisineCategories: [String] {
        let cuisines = Set(allRestaurants.map { $0.cuisineType }).filter { !$0.isEmpty }
        return cuisines.sorted()
    }

    // Where the last search was centred, so the map can tell how far the user
    // has panned and offer to search again.
    private(set) var lastSearchCenter: CLLocationCoordinate2D?

    private let dataService: any DataServiceProtocol
    private let locationProvider = LocationProvider()
    private var searchTask: Task<Void, Never>?

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    // MARK: - Loading

    // Passing a coordinate searches there instead of at the user's location —
    // that's what "Search this area" on the map does after a pan.
    func loadNearby(at coordinate: CLLocationCoordinate2D? = nil) async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        let center: CLLocationCoordinate2D
        if let coordinate {
            center = coordinate
        } else if let location = await locationProvider.currentLocation() {
            center = location.coordinate
        } else {
            await loadSavedPlaces()
            return
        }

        isShowingSavedPlacesOnly = false
        lastSearchCenter = center

        do {
            let places = try await PlaceSearchService.searchRestaurants(
                matching: searchText,
                near: center
            )
            allRestaurants = await mergingCrowdData(into: places)
            applyFilters()
        } catch {
            // A failed MapKit search still leaves the saved places worth showing.
            await loadSavedPlaces()
            errorMessage = "Couldn't search nearby. Showing places you've saved."
        }
    }

    // Fallback for a simulator with no location, a denied permission, or a
    // failed search: the restaurants already in the database.
    private func loadSavedPlaces() async {
        isShowingSavedPlacesOnly = true

        do {
            allRestaurants = try await dataService.fetchAllRestaurants()
            applyFilters()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // Overlays whatever the community has built up onto raw MapKit results.
    // A place nobody has touched simply stays as MapKit returned it.
    private func mergingCrowdData(into places: [Restaurant]) async -> [Restaurant] {
        let placeIds = places.compactMap(\.mapkitPlaceId)
        guard !placeIds.isEmpty else { return places }

        do {
            let known = try await dataService.fetchRestaurants(mapkitPlaceIds: placeIds)
            let rowsByPlaceId = Dictionary(
                known.compactMap { row in row.mapkitPlaceId.map { ($0, row) } },
                uniquingKeysWith: { first, _ in first }
            )

            return places.map { place in
                guard
                    let placeId = place.mapkitPlaceId,
                    let row = rowsByPlaceId[placeId]
                else { return place }
                return place.merging(persisted: row)
            }
        } catch {
            // Losing the crowd overlay is a degraded result, not a failure —
            // the search results themselves are still perfectly usable.
            return places
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await loadNearby()
        }
    }

    // MARK: - Filtering

    // Only the cuisine chips filter locally now; the text query is handled by
    // MapKit, which has already matched against far more than name and cuisine.
    private func applyFilters() {
        guard let cuisine = selectedCuisine else {
            filteredRestaurants = allRestaurants
            return
        }
        filteredRestaurants = allRestaurants.filter { $0.cuisineType == cuisine }
    }

    func clearCuisineFilter() {
        selectedCuisine = nil
    }

    func toggleCuisineFilter(_ cuisine: String) {
        if selectedCuisine == cuisine {
            selectedCuisine = nil
        } else {
            selectedCuisine = cuisine
        }
    }
}

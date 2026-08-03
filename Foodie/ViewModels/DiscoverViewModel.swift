import Foundation
import Observation

@Observable
@MainActor
class DiscoverViewModel {
    var allRestaurants: [Restaurant] = []
    var filteredRestaurants: [Restaurant] = []
    var isLoading = false
    var errorMessage: String?
    var hasLoadedOnce = false

    var searchText: String = "" {
        didSet { applyFilters() }
    }
    var selectedCuisine: String? = nil {
        didSet { applyFilters() }
    }

    var cuisineCategories: [String] {
        let cuisines = Set(allRestaurants.map { $0.cuisineType }).filter { !$0.isEmpty }
        return cuisines.sorted()
    }

    private let dataService: any DataServiceProtocol

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    func loadRestaurants() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            allRestaurants = try await dataService.fetchAllRestaurants()
            applyFilters()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    private func applyFilters() {
        var results = allRestaurants

        // Filter by search text (name or cuisine)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(query) ||
                $0.cuisineType.lowercased().contains(query)
            }
        }

        // Filter by selected cuisine category
        if let cuisine = selectedCuisine {
            results = results.filter { $0.cuisineType == cuisine }
        }

        filteredRestaurants = results
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

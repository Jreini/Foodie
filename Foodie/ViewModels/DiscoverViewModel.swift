import Foundation
import Observation

@Observable
class DiscoverViewModel {
    var allRestaurants: [Restaurant] = []
    var filteredRestaurants: [Restaurant] = []
    var searchText: String = "" {
        didSet { applyFilters() }
    }
    var selectedCuisine: String? = nil {
        didSet { applyFilters() }
    }

    var cuisineCategories: [String] {
        let cuisines = Set(allRestaurants.map { $0.cuisineType })
        return cuisines.sorted()
    }

    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol = MockDataService()) {
        self.dataService = dataService
    }

    func loadRestaurants() {
        allRestaurants = dataService.fetchAllRestaurants()
        applyFilters()
    }

    func fetchReviews(for restaurantId: UUID) -> [Review] {
        dataService.fetchReviews(for: restaurantId)
    }

    func findUser(by userId: UUID) -> User? {
        dataService.fetchAllUsers().first(where: { $0.id == userId })
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

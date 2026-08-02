import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
class TastingListViewModel {
    var entries: [TastingListEntry] = []
    var restaurants: [UUID: Restaurant] = [:]
    var randomPick: Restaurant? = nil

    var isLoading = false
    var errorMessage: String?

    private let dataService: any DataServiceProtocol
    private var currentUserId: UUID?

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    func loadTastingList() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let currentUser = try await dataService.fetchCurrentUser()
            currentUserId = currentUser.id

            async let entriesTask = dataService.fetchTastingList(for: currentUser.id)
            async let restaurantsTask = dataService.fetchAllRestaurants()

            entries = try await entriesTask
            restaurants = Dictionary(
                uniqueKeysWithValues: try await restaurantsTask.map { ($0.id, $0) }
            )
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func restaurantForEntry(_ entry: TastingListEntry) -> Restaurant? {
        restaurants[entry.restaurantId]
    }

    // Removes locally first so the row disappears under the finger, then syncs.
    // A failed delete puts the entry back rather than lying about the result.
    func removeEntry(at offsets: IndexSet) async {
        let removed = offsets.map { entries[$0] }
        entries.remove(atOffsets: offsets)

        do {
            for entry in removed {
                try await dataService.removeFromTastingList(restaurantId: entry.restaurantId)
            }
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            await loadTastingList()
        }
    }

    func pickRandomEntry() {
        guard !entries.isEmpty else { return }
        if let entry = entries.randomElement() {
            randomPick = restaurants[entry.restaurantId]
        }
    }

    // Restaurants not yet on the Tasting List, for the picker sheet
    var availableRestaurants: [Restaurant] {
        let existingIds = Set(entries.map { $0.restaurantId })
        return restaurants.values
            .filter { !existingIds.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    func addRestaurant(_ restaurant: Restaurant, notes: String = "") async {
        guard !entries.contains(where: { $0.restaurantId == restaurant.id }) else { return }

        do {
            let entry = try await dataService.addToTastingList(
                restaurantId: restaurant.id,
                notes: notes
            )
            entries.insert(entry, at: 0)
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }
}

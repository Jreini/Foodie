import Foundation
import Observation

@Observable
@MainActor
class DecisionEngineViewModel {
    var likedRestaurants: [Restaurant] = []
    var tastingListRestaurants: [Restaurant] = []
    var allRestaurants: [Restaurant] = []
    var friends: [User] = []
    // The result after a "pick" action
    var pickedRestaurant: Restaurant? = nil
    var isAnimatingPick: Bool = false

    var isLoading = false
    var errorMessage: String?

    private let dataService: any DataServiceProtocol

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let currentUser = try await dataService.fetchCurrentUser()

            async let restaurantsTask = dataService.fetchAllRestaurants()
            async let friendsTask = dataService.fetchFriends(for: currentUser.id)
            async let likedTask = dataService.fetchLikedRestaurantIds(for: currentUser.id)
            async let tastingTask = dataService.fetchTastingList(for: currentUser.id)

            allRestaurants = try await restaurantsTask
            friends = try await friendsTask

            let likedIds = Set(try await likedTask)
            likedRestaurants = allRestaurants.filter { likedIds.contains($0.id) }

            let tastingIds = Set(try await tastingTask.map(\.restaurantId))
            tastingListRestaurants = allRestaurants.filter { tastingIds.contains($0.id) }
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // Picks a random restaurant from liked places + tasting list combined
    func pickRandomForMe() async {
        let pool = Array(Set(likedRestaurants + tastingListRestaurants))
        guard !pool.isEmpty else { return }
        isAnimatingPick = true

        // Brief "spin" before the reveal. Structured concurrency rather than
        // asyncAfter, so the delay stays on the main actor with the state.
        try? await Task.sleep(for: .milliseconds(600))
        pickedRestaurant = pool.randomElement()
        isAnimatingPick = false
    }

    // Roll the Dice for a group: mock-picks a random spot the group might overlap on
    // For real data this would aggregate each friend's likes + tasting list
    func pickForGroup(selectedFriendIds: [UUID]) -> Restaurant? {
        guard !selectedFriendIds.isEmpty else { return nil }

        // Include the user's own pool as the overlap seed
        let pool = Array(Set(likedRestaurants + tastingListRestaurants))
        return (pool.isEmpty ? allRestaurants : pool).randomElement()
    }

    // Animated version of group pick used by Roll the Dice
    func rollForGroup(selectedFriendIds: [UUID]) async {
        guard !selectedFriendIds.isEmpty else { return }
        isAnimatingPick = true

        try? await Task.sleep(for: .milliseconds(600))
        pickedRestaurant = pickForGroup(selectedFriendIds: selectedFriendIds)
        isAnimatingPick = false
    }

    // Suggests a restaurant nobody in the group has visited
    // When selectedFriendIds is empty, acts as a solo "discover a new taste"
    func discoverNewTaste(selectedFriendIds: [UUID] = []) -> Restaurant? {
        // In a real app, exclude places anyone in the group has reviewed
        // For mock: exclude the user's liked + tasting list restaurants
        let visitedIds = Set(likedRestaurants.map { $0.id } + tastingListRestaurants.map { $0.id })
        let unvisited = allRestaurants.filter { !visitedIds.contains($0.id) }
        return unvisited.randomElement() ?? allRestaurants.randomElement()
    }

    func pickRandomFromTastingList() -> Restaurant? {
        tastingListRestaurants.randomElement()
    }

    // Resets animation + prior picks (e.g. when switching Solo/Group mode)
    func resetPick() {
        pickedRestaurant = nil
        isAnimatingPick = false
    }
}

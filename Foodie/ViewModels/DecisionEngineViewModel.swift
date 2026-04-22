import Foundation
import Observation

@Observable
class DecisionEngineViewModel {
    var likedRestaurants: [Restaurant] = []
    var tastingListRestaurants: [Restaurant] = []
    var allRestaurants: [Restaurant] = []
    var friends: [User] = []
    // The result after a "pick" action
    var pickedRestaurant: Restaurant? = nil
    var isAnimatingPick: Bool = false

    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol = MockDataService()) {
        self.dataService = dataService
    }

    func loadData() {
        let currentUser = dataService.fetchCurrentUser()
        allRestaurants = dataService.fetchAllRestaurants()
        friends = dataService.fetchFriends(for: currentUser.id)

        // Build liked restaurants from liked IDs
        let likedIds = dataService.fetchLikedRestaurantIds(for: currentUser.id)
        likedRestaurants = allRestaurants.filter { likedIds.contains($0.id) }

        // Build tasting list restaurants
        let tastingEntries = dataService.fetchTastingList(for: currentUser.id)
        let tastingIds = tastingEntries.map { $0.restaurantId }
        tastingListRestaurants = allRestaurants.filter { tastingIds.contains($0.id) }
    }

    // Picks a random restaurant from liked places + tasting list combined
    func pickRandomForMe() {
        let pool = Array(Set(likedRestaurants + tastingListRestaurants))
        guard !pool.isEmpty else { return }
        isAnimatingPick = true

        // Simulate brief "spin" delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            pickedRestaurant = pool.randomElement()
            isAnimatingPick = false
        }
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
    func rollForGroup(selectedFriendIds: [UUID]) {
        guard !selectedFriendIds.isEmpty else { return }
        isAnimatingPick = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            pickedRestaurant = pickForGroup(selectedFriendIds: selectedFriendIds)
            isAnimatingPick = false
        }
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

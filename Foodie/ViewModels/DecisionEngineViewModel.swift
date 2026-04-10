import Foundation
import Observation

@Observable
class DecisionEngineViewModel {
    var likedRestaurants: [Restaurant] = []
    var bucketListRestaurants: [Restaurant] = []
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

        // Build bucket list restaurants
        let bucketEntries = dataService.fetchBucketList(for: currentUser.id)
        let bucketIds = bucketEntries.map { $0.restaurantId }
        bucketListRestaurants = allRestaurants.filter { bucketIds.contains($0.id) }
    }

    // Picks a random restaurant from liked places + bucket list combined
    func pickRandomForMe() {
        let pool = Array(Set(likedRestaurants + bucketListRestaurants))
        guard !pool.isEmpty else { return }
        isAnimatingPick = true

        // Simulate brief "spin" delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            pickedRestaurant = pool.randomElement()
            isAnimatingPick = false
        }
    }

    // Finds restaurants that overlap across selected friends' liked + bucket list
    // For mock data, returns restaurants liked by at least one friend from the pool
    func pickForGroup(selectedFriendIds: [UUID]) -> Restaurant? {
        guard !selectedFriendIds.isEmpty else { return nil }

        // In a real app this would aggregate each friend's likes/bucket list
        // For now, pick a random restaurant from the full pool as a stand-in
        let pool = allRestaurants
        return pool.randomElement()
    }

    // Suggests a restaurant nobody in the group has visited
    func discoverForGroup(selectedFriendIds: [UUID]) -> Restaurant? {
        // In a real app, exclude places anyone in the group has reviewed
        // For mock: pick randomly from all restaurants
        let visitedIds = Set(likedRestaurants.map { $0.id } + bucketListRestaurants.map { $0.id })
        let unvisited = allRestaurants.filter { !visitedIds.contains($0.id) }
        return unvisited.randomElement() ?? allRestaurants.randomElement()
    }

    func pickRandomFromBucketList() -> Restaurant? {
        bucketListRestaurants.randomElement()
    }
}

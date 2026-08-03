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

    // Roll the Dice for a group.
    //
    // The overlap is computed in Postgres (`group_pick_candidates`), which
    // returns restaurants ranked by how many of the group saved or liked them.
    // Doing it server-side is what makes it correct: the client can't see
    // friends' full lists in one place, and RLS is what decides whose rows
    // count — passing in someone who isn't a friend simply contributes nothing.
    func pickForGroup(selectedFriendIds: [UUID]) async -> Restaurant? {
        guard !selectedFriendIds.isEmpty else { return nil }

        do {
            let ranked = try await dataService.groupPickCandidates(friendIds: selectedFriendIds)
            let byId = Dictionary(
                allRestaurants.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            // Ties are common with small groups, so pick randomly among the
            // joint top scorers rather than always returning the same one.
            let candidates = ranked.compactMap { byId[$0] }
            guard !candidates.isEmpty else { return fallbackPick() }

            let topTier = candidates.prefix(max(1, min(3, candidates.count)))
            return topTier.randomElement()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            return fallbackPick()
        }
    }

    // Nobody in the group has saved anything in common — better to suggest
    // something than to show an empty result.
    private func fallbackPick() -> Restaurant? {
        let ownPool = Array(Set(likedRestaurants + tastingListRestaurants))
        return (ownPool.isEmpty ? allRestaurants : ownPool).randomElement()
    }

    // Animated version of group pick used by Roll the Dice
    func rollForGroup(selectedFriendIds: [UUID]) async {
        guard !selectedFriendIds.isEmpty else { return }
        isAnimatingPick = true

        // Run the spin and the query together so the animation isn't just
        // added on top of however long the network takes.
        async let spin: Void = Task.sleep(for: .milliseconds(600))
        async let pick = pickForGroup(selectedFriendIds: selectedFriendIds)

        let result = await pick
        try? await spin

        pickedRestaurant = result
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

import Foundation

// Contract for all data operations — swap MockDataService for a real backend later
protocol DataServiceProtocol {
    func fetchCurrentUser() -> User
    func fetchAllUsers() -> [User]
    func fetchFriends(for userId: UUID) -> [User]

    func fetchAllRestaurants() -> [Restaurant]
    func fetchRestaurant(by id: UUID) -> Restaurant?

    func fetchReviews(for restaurantId: UUID) -> [Review]
    func fetchReviews(by userId: UUID) -> [Review]

    func fetchTastingList(for userId: UUID) -> [TastingListEntry]
    func fetchActivityFeed(for userId: UUID) -> [FriendActivity]

    func fetchLikedRestaurantIds(for userId: UUID) -> [UUID]
}

import Foundation

// Contract for all data operations.
//
// Two implementations: `SupabaseDataService` (live) and `MockDataService`
// (previews and offline development). Everything is `async throws` because the
// live one crosses the network — the mock satisfies that trivially.
//
// "Current user" is implicit in the live implementation: it comes from the
// session, not from a caller-supplied id. The `for userId:` parameters that
// remain are for looking at *other* people, which friend features need.
protocol DataServiceProtocol {

    // MARK: - People

    func fetchCurrentUser() async throws -> User
    func fetchAllUsers() async throws -> [User]
    func fetchFriends(for userId: UUID) async throws -> [User]

    // MARK: - Restaurants

    func fetchAllRestaurants() async throws -> [Restaurant]
    func fetchRestaurant(by id: UUID) async throws -> Restaurant?

    // MARK: - Reviews

    func fetchReviews(for restaurantId: UUID) async throws -> [Review]
    func fetchReviews(by userId: UUID) async throws -> [Review]

    // MARK: - Lists and Likes

    func fetchTastingList(for userId: UUID) async throws -> [TastingListEntry]
    func fetchLikedRestaurantIds(for userId: UUID) async throws -> [UUID]

    // MARK: - Feed

    func fetchActivityFeed(for userId: UUID) async throws -> [FriendActivity]

    // MARK: - Writes

    // All writes act as the signed-in user; RLS enforces that server-side, so
    // there is deliberately no "as this user" parameter to get wrong.

    @discardableResult
    func addToTastingList(restaurantId: UUID, notes: String) async throws -> TastingListEntry

    func removeFromTastingList(restaurantId: UUID) async throws

    func setLiked(_ liked: Bool, restaurantId: UUID) async throws

    @discardableResult
    func submitReview(
        restaurantId: UUID,
        rating: Int,
        text: String,
        moodTags: [String],
        tierPlacement: RestaurantTier
    ) async throws -> Review
}

// Resolves which implementation the app uses.
//
// View models default to `DataServices.current` rather than constructing a
// service directly, so SwiftUI previews get mock data automatically instead of
// hitting the network (and failing, since previews have no session).
enum DataServices {
    // Read from the main actor only — view models are all `@MainActor` by way
    // of SwiftUI, and the mock implementation holds mutable sample data.
    nonisolated(unsafe) static let current: any DataServiceProtocol = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return MockDataService()
        }
        #endif
        return SupabaseDataService()
    }()
}

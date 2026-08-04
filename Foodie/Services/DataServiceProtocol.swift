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

    // How many accepted friends someone has. Counted server-side because the
    // friendships policy only returns edges the caller is part of — asking the
    // client to count them would report 1 for every friend.
    func friendCount(for userId: UUID) async throws -> Int

    // MARK: - Friendships

    // Username prefix/substring search. Excludes nobody — filtering out people
    // you're already connected to is the UI's job, since it wants to show them
    // with a different button rather than hide them.
    func searchUsers(username: String) async throws -> [User]

    // Every edge the signed-in user is part of, in any state. RLS returns only
    // those, so one call covers friends, incoming, and outgoing requests.
    func fetchFriendships() async throws -> [Friendship]

    func sendFriendRequest(to userId: UUID) async throws
    func acceptFriendRequest(friendshipId: UUID) async throws
    // Declining and unfriending are both "remove the edge" — the difference is
    // only which state it was in.
    func removeFriendship(friendshipId: UUID) async throws

    // Restaurants the caller and the given friends are collectively interested
    // in, most-shared first. Computed server-side.
    func groupPickCandidates(friendIds: [UUID]) async throws -> [UUID]

    // MARK: - Shared Lists

    func fetchLists() async throws -> [SharedList]
    func createList(name: String, emoji: String?) async throws -> SharedList
    func deleteList(id: UUID) async throws

    func fetchListEntries(listId: UUID) async throws -> [SharedListEntry]
    @discardableResult
    func addListEntry(listId: UUID, restaurantId: UUID, notes: String) async throws -> SharedListEntry
    func removeListEntry(entryId: UUID) async throws

    func fetchListMembers(listId: UUID) async throws -> [SharedListMember]
    func addListMember(listId: UUID, userId: UUID) async throws
    func removeListMember(listId: UUID, userId: UUID) async throws

    // Emits whenever anyone changes this list's entries. The live
    // implementation opens a Realtime channel; the mock returns a stream that
    // never fires, so previews don't need a connection. Cancelling the
    // consuming task tears the subscription down.
    func listEntriesChanged(listId: UUID) -> AsyncStream<Void>

    // MARK: - Restaurants

    func fetchAllRestaurants() async throws -> [Restaurant]
    func fetchRestaurant(by id: UUID) async throws -> Restaurant?

    // Looks up the rows behind a set of MapKit results, so search results can
    // be shown with whatever crowd data the community has built up.
    func fetchRestaurants(mapkitPlaceIds: [String]) async throws -> [Restaurant]

    // Makes sure a place exists in the database, returning the canonical row.
    // MapKit results are not persisted until someone interacts with them, so
    // every write path calls this first.
    @discardableResult
    func ensureRestaurantPersisted(_ restaurant: Restaurant) async throws -> Restaurant

    // MARK: - Reviews

    func fetchReviews(for restaurantId: UUID) async throws -> [Review]
    func fetchReviews(by userId: UUID) async throws -> [Review]

    // MARK: - Lists and Likes

    func fetchTastingList(for userId: UUID) async throws -> [TastingListEntry]
    func fetchLikedRestaurantIds(for userId: UUID) async throws -> [UUID]

    // MARK: - Feed

    // `before` pages backwards through time; nil starts at the newest.
    func fetchActivityFeed(for userId: UUID, before: Date?) async throws -> [FriendActivity]

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
        photoPaths: [String],
        tierPlacement: RestaurantTier
    ) async throws -> Review

    // MARK: - Notifications

    // The signed-in user's inbox, newest first. No `for userId:` parameter —
    // RLS returns only your own, and there is no legitimate reason to ask for
    // anyone else's.
    func fetchNotifications() async throws -> [AppNotification]

    // Counted server-side rather than by loading the inbox, because the badge
    // is drawn on a screen that has no other reason to fetch notifications.
    func unreadNotificationCount() async throws -> Int

    func markNotificationsRead(ids: [UUID]) async throws

    // MARK: - Devices

    // Claims an APNs token for the signed-in user. `isSandbox` records which
    // Apple host the token belongs to — a debug build's token is rejected by
    // the production one and vice versa.
    func registerDeviceToken(_ token: String, isSandbox: Bool) async throws

    // Detaches a token on sign-out, so the next account on this phone doesn't
    // inherit the last one's notifications.
    func unregisterDeviceToken(_ token: String) async throws

    // MARK: - Account

    // Removes the account and everything owned by it. Irreversible, and
    // required by the App Store for any app that offers sign-in.
    func deleteAccount() async throws
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

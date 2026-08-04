import Foundation
import Observation

@Observable
@MainActor
class FeedViewModel {
    var activities: [FriendActivity] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    // Distinguishes "no friends yet" from "hasn't loaded yet" — the two want
    // very different empty states.
    var hasLoadedOnce = false

    // False once a page comes back short, so the list stops asking.
    private(set) var hasMore = true

    // Badges the Friends button so a waiting request doesn't sit unanswered on
    // a screen nobody opens. One small query — the friendships policy already
    // limits it to the caller's own edges.
    private(set) var pendingRequestCount = 0

    // Badges the bell. Counted server-side so this stays one cheap query rather
    // than loading an inbox nobody has opened.
    private(set) var unreadNotificationCount = 0

    private let dataService: any DataServiceProtocol
    private var currentUserId: UUID?

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    func loadActivityFeed() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            let currentUser = try await dataService.fetchCurrentUser()
            currentUserId = currentUser.id

            let page = try await dataService.fetchActivityFeed(for: currentUser.id, before: nil)
            activities = page
            hasMore = !page.isEmpty

            await loadBadgeCounts(for: currentUser.id)
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // Re-counts only the badges, for coming back to the Feed after reading the
    // inbox or answering a request. The feed itself is deliberately left alone:
    // the activity on screen didn't change because a notification was read, and
    // reloading it would scroll the user back to the top for nothing.
    func refreshBadges() async {
        guard let currentUserId else { return }
        await loadBadgeCounts(for: currentUserId)
    }

    // Both badges, deliberately swallowing their errors: a badge that can't be
    // counted is worth nothing, and failing the whole feed over one would be
    // absurd. Run concurrently — neither depends on the other, and this happens
    // after the feed itself is already on screen.
    private func loadBadgeCounts(for userId: UUID) async {
        async let friendships = try? await dataService.fetchFriendships()
        async let unread = try? await dataService.unreadNotificationCount()

        let edges = await friendships ?? []
        pendingRequestCount = edges.filter { $0.isIncomingRequest(for: userId) }.count
        unreadNotificationCount = await unread ?? 0
    }

    // Pages backwards from the oldest row on screen. Keyset rather than offset,
    // because the feed grows at the top and an offset would skip or repeat rows
    // as new activity arrives mid-scroll.
    func loadMoreIfNeeded(currentItem: FriendActivity) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard activities.suffix(5).contains(where: { $0.id == currentItem.id }) else { return }
        guard let currentUserId, let oldest = activities.last?.timestamp else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await dataService.fetchActivityFeed(for: currentUserId, before: oldest)

            // Ids already on screen are dropped: rows sharing a timestamp can
            // straddle a page boundary.
            let existing = Set(activities.map(\.id))
            let fresh = page.filter { !existing.contains($0.id) }

            activities.append(contentsOf: fresh)
            hasMore = !page.isEmpty
        } catch {
            // A failed page shouldn't wipe the feed already on screen; stop
            // paging and let a pull-to-refresh recover.
            hasMore = false
        }
    }

    func restaurant(for activity: FriendActivity) -> Restaurant {
        activity.restaurant
    }
}

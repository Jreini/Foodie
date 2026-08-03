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
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
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

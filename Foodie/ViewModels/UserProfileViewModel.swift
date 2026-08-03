import Foundation
import Observation

// Backs somebody else's profile.
//
// Deliberately not a variant of `ProfileViewModel`: that one reads the signed-in
// account and can assume every query returns everything. Here the answer depends
// on how the two people are related, and the database is what decides —
// reviews are readable by anyone signed in, but the `likes` and `tasting_list`
// policies return rows only to the owner and their accepted friends.
//
// So `canSeeSavedRestaurants` is not a permission check the client is
// performing. It's the client knowing in advance what the server will withhold,
// so those sections can say "friends only" instead of a misleading "empty".
@Observable
@MainActor
final class UserProfileViewModel {

    let user: User

    var reviews: [Review] = []
    var likedRestaurants: [Restaurant] = []
    var tastingListRestaurants: [Restaurant] = []
    var friendCount = 0

    var friendshipState: FriendshipState = .none
    // Disables the friendship button while a request is in flight, so a double
    // tap can't send two.
    var isUpdatingFriendship = false

    var isLoading = false
    var errorMessage: String?
    var hasLoadedOnce = false

    var selectedSegment: ProfileSegment = .reviews

    var reviewCount: Int { reviews.count }

    // Nil rather than 0 for someone who isn't allowed to see the list — the
    // stat shows a dash instead of claiming they've saved nothing.
    var visibleTastingListCount: Int? {
        canSeeSavedRestaurants ? tastingListRestaurants.count : nil
    }

    // Their saved restaurants are visible to friends and to themselves. For
    // anyone else the queries below come back empty by policy.
    var canSeeSavedRestaurants: Bool {
        switch friendshipState {
        case .friends, .currentUser: return true
        case .none, .requestSent, .requestReceived: return false
        }
    }

    private let dataService: any DataServiceProtocol
    private var allRestaurants: [Restaurant] = []
    private var friendships: [Friendship] = []
    private var currentUserId: UUID?

    init(user: User, dataService: any DataServiceProtocol = DataServices.current) {
        self.user = user
        self.dataService = dataService
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            // The relationship has to resolve first: it decides whether asking
            // for their saved restaurants is worth a round trip at all.
            let currentUser = try await dataService.fetchCurrentUser()
            currentUserId = currentUser.id
            friendships = try await dataService.fetchFriendships()
            friendshipState = FriendshipState.between(
                currentUserId: currentUser.id,
                otherUserId: user.id,
                friendships: friendships
            )

            async let restaurantsTask = dataService.fetchAllRestaurants()
            async let reviewsTask = dataService.fetchReviews(by: user.id)
            // Counted server-side: RLS hides their friendship rows from us.
            async let friendCountTask = dataService.friendCount(for: user.id)

            allRestaurants = try await restaurantsTask
            reviews = try await reviewsTask
            friendCount = try await friendCountTask

            if canSeeSavedRestaurants {
                async let likedTask = dataService.fetchLikedRestaurantIds(for: user.id)
                async let tastingTask = dataService.fetchTastingList(for: user.id)

                let liked = Set(try await likedTask)
                likedRestaurants = allRestaurants.filter { liked.contains($0.id) }

                let tastingIds = Set(try await tastingTask.map(\.restaurantId))
                tastingListRestaurants = allRestaurants.filter { tastingIds.contains($0.id) }
            } else {
                likedRestaurants = []
                tastingListRestaurants = []
            }
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func restaurantForReview(_ review: Review) -> Restaurant? {
        allRestaurants.first(where: { $0.id == review.restaurantId })
    }

    // MARK: - Friendship

    func sendRequest() async {
        await mutateFriendship {
            try await dataService.sendFriendRequest(to: user.id)
        }
    }

    func acceptRequest() async {
        guard case .requestReceived(let friendshipId) = friendshipState else { return }
        await mutateFriendship {
            try await dataService.acceptFriendRequest(friendshipId: friendshipId)
        }
    }

    func removeFriend() async {
        guard case .friends(let friendshipId) = friendshipState else { return }
        await mutateFriendship {
            try await dataService.removeFriendship(friendshipId: friendshipId)
        }
    }

    // Every friendship change reshapes what this screen may show — accepting a
    // request unlocks two sections — so each one reloads rather than patching
    // local state.
    private func mutateFriendship(_ action: () async throws -> Void) async {
        guard !isUpdatingFriendship else { return }
        isUpdatingFriendship = true
        errorMessage = nil

        do {
            try await action()
        } catch let error as FriendRequestError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }

        isUpdatingFriendship = false
        await load()
    }
}

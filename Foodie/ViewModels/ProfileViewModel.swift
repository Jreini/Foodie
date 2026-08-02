import Foundation
import Observation

@Observable
@MainActor
class ProfileViewModel {
    var currentUser: User?
    var userReviews: [Review] = []
    var likedRestaurants: [Restaurant] = []
    var tastingListRestaurants: [Restaurant] = []
    var allRestaurants: [Restaurant] = []

    var isLoading = false
    var errorMessage: String?

    // Tracks which segment is selected in the profile
    var selectedSegment: ProfileSegment = .reviews

    enum ProfileSegment: String, CaseIterable {
        case reviews = "Reviews"
        case liked = "Liked"
        case tastingList = "Tasting List"
    }

    var reviewCount: Int { userReviews.count }
    var friendCount: Int { currentUser?.friendCount ?? 0 }
    var tastingListCount: Int { tastingListRestaurants.count }

    private let dataService: any DataServiceProtocol

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    func loadProfile() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await dataService.fetchCurrentUser()
            currentUser = user

            // Independent queries, so run them concurrently rather than in a
            // chain of four round trips.
            async let restaurantsTask = dataService.fetchAllRestaurants()
            async let reviewsTask = dataService.fetchReviews(by: user.id)
            async let likedTask = dataService.fetchLikedRestaurantIds(for: user.id)
            async let tastingTask = dataService.fetchTastingList(for: user.id)

            allRestaurants = try await restaurantsTask
            userReviews = try await reviewsTask

            let liked = Set(try await likedTask)
            likedRestaurants = allRestaurants.filter { liked.contains($0.id) }

            let tastingIds = Set(try await tastingTask.map(\.restaurantId))
            tastingListRestaurants = allRestaurants.filter { tastingIds.contains($0.id) }
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func restaurantForReview(_ review: Review) -> Restaurant? {
        allRestaurants.first(where: { $0.id == review.restaurantId })
    }
}

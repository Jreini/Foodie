import Foundation
import Observation

@Observable
class ProfileViewModel {
    var currentUser: User?
    var userReviews: [Review] = []
    var likedRestaurants: [Restaurant] = []
    var tastingListRestaurants: [Restaurant] = []
    var allRestaurants: [Restaurant] = []

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

    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol = MockDataService()) {
        self.dataService = dataService
    }

    func loadProfile() {
        let user = dataService.fetchCurrentUser()
        currentUser = user
        allRestaurants = dataService.fetchAllRestaurants()

        userReviews = dataService.fetchReviews(by: user.id)

        let likedIds = dataService.fetchLikedRestaurantIds(for: user.id)
        likedRestaurants = allRestaurants.filter { likedIds.contains($0.id) }

        let tastingEntries = dataService.fetchTastingList(for: user.id)
        let tastingIds = tastingEntries.map { $0.restaurantId }
        tastingListRestaurants = allRestaurants.filter { tastingIds.contains($0.id) }
    }

    func restaurantForReview(_ review: Review) -> Restaurant? {
        allRestaurants.first(where: { $0.id == review.restaurantId })
    }
}

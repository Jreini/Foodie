import Foundation
import Observation

@Observable
class ProfileViewModel {
    var currentUser: User?
    var userReviews: [Review] = []
    var likedRestaurants: [Restaurant] = []
    var bucketListRestaurants: [Restaurant] = []
    var allRestaurants: [Restaurant] = []

    // Tracks which segment is selected in the profile
    var selectedSegment: ProfileSegment = .reviews

    enum ProfileSegment: String, CaseIterable {
        case reviews = "Reviews"
        case liked = "Liked"
        case bucketList = "Bucket List"
    }

    var reviewCount: Int { userReviews.count }
    var friendCount: Int { currentUser?.friendCount ?? 0 }
    var bucketListCount: Int { bucketListRestaurants.count }

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

        let bucketEntries = dataService.fetchBucketList(for: user.id)
        let bucketIds = bucketEntries.map { $0.restaurantId }
        bucketListRestaurants = allRestaurants.filter { bucketIds.contains($0.id) }
    }

    func restaurantForReview(_ review: Review) -> Restaurant? {
        allRestaurants.first(where: { $0.id == review.restaurantId })
    }
}

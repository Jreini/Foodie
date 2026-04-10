import Foundation
import Observation

@Observable
class FeedViewModel {
    var activities: [FriendActivity] = []

    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol = MockDataService()) {
        self.dataService = dataService
    }

    func loadActivityFeed() {
        let currentUser = dataService.fetchCurrentUser()
        activities = dataService.fetchActivityFeed(for: currentUser.id)
    }

    func restaurant(for activity: FriendActivity) -> Restaurant {
        activity.restaurant
    }
}

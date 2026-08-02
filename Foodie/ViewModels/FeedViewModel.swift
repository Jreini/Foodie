import Foundation
import Observation

@Observable
@MainActor
class FeedViewModel {
    var activities: [FriendActivity] = []
    var isLoading = false
    var errorMessage: String?

    // Distinguishes "no friends yet" from "hasn't loaded yet" — the two want
    // very different empty states.
    var hasLoadedOnce = false

    private let dataService: any DataServiceProtocol

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
            activities = try await dataService.fetchActivityFeed(for: currentUser.id)
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func restaurant(for activity: FriendActivity) -> Restaurant {
        activity.restaurant
    }
}

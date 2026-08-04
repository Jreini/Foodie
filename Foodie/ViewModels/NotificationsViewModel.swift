import Foundation
import Observation

@Observable
@MainActor
final class NotificationsViewModel {
    private(set) var notifications: [AppNotification] = []
    var isLoading = false
    var errorMessage: String?

    // Separates "nothing has arrived yet" from "hasn't loaded yet", which want
    // different empty states.
    private(set) var hasLoadedOnce = false

    private let dataService: any DataServiceProtocol

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            notifications = try await dataService.fetchNotifications()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // Opening the inbox is what marks things read — there is no per-row control,
    // because a list you had to tap through twice to clear would be worse than
    // one that just settles down after you've looked at it.
    //
    // The unread styling is left on screen for this viewing: rows that go grey
    // as you look at them make it hard to see what was new. The next load shows
    // them read.
    func markVisibleRead() async {
        let unread = notifications.filter(\.isUnread).map(\.id)
        guard !unread.isEmpty else { return }

        // Failure is silent by design: the rows are already on screen and the
        // user has seen them. Surfacing "couldn't mark as read" would be noise
        // about something they never asked for.
        try? await dataService.markNotificationsRead(ids: unread)
    }
}

import Foundation
import Observation

@Observable
@MainActor
class FriendsViewModel {
    var friends: [User] = []
    var incomingRequests: [PendingRequest] = []
    var outgoingRequests: [PendingRequest] = []

    var searchResults: [SearchResult] = []
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    var isLoading = false
    var isSearching = false
    var errorMessage: String?

    // A person plus how you relate to them, so a row knows which button to show.
    struct SearchResult: Identifiable, Hashable {
        let user: User
        let state: FriendshipState
        var id: UUID { user.id }
    }

    struct PendingRequest: Identifiable, Hashable {
        let friendship: Friendship
        let user: User
        var id: UUID { friendship.id }
    }

    private let dataService: any DataServiceProtocol
    private var currentUserId: UUID?
    private var friendships: [Friendship] = []
    private var searchTask: Task<Void, Never>?

    init(dataService: any DataServiceProtocol = DataServices.current) {
        self.dataService = dataService
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let currentUser = try await dataService.fetchCurrentUser()
            currentUserId = currentUser.id
            friendships = try await dataService.fetchFriendships()

            // One lookup for everyone referenced by any edge, rather than a
            // request per row.
            let otherIds = friendships.map { $0.otherUserId(from: currentUser.id) }
            let people = try await usersById(ids: otherIds)

            friends = friendships
                .filter { $0.status == .accepted }
                .compactMap { people[$0.otherUserId(from: currentUser.id)] }
                .sorted { $0.name < $1.name }

            incomingRequests = friendships
                .filter { $0.isIncomingRequest(for: currentUser.id) }
                .compactMap { edge in
                    people[edge.otherUserId(from: currentUser.id)]
                        .map { PendingRequest(friendship: edge, user: $0) }
                }

            outgoingRequests = friendships
                .filter { $0.isOutgoingRequest(for: currentUser.id) }
                .compactMap { edge in
                    people[edge.otherUserId(from: currentUser.id)]
                        .map { PendingRequest(friendship: edge, user: $0) }
                }

            refreshSearchStates()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    private func usersById(ids: [UUID]) async throws -> [UUID: User] {
        guard !ids.isEmpty else { return [:] }
        let all = try await dataService.fetchAllUsers()
        let wanted = Set(ids)
        return Dictionary(
            all.filter { wanted.contains($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()

        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            defer { isSearching = false }
            do {
                let users = try await dataService.searchUsers(username: term)
                guard !Task.isCancelled else { return }
                searchResults = users.map(makeResult)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = DataLoadFailure.message(for: error)
            }
        }
    }

    private func makeResult(for user: User) -> SearchResult {
        SearchResult(
            user: user,
            state: FriendshipState.between(
                currentUserId: currentUserId ?? UUID(),
                otherUserId: user.id,
                friendships: friendships
            )
        )
    }

    // Keeps buttons honest after a request is sent or accepted, without
    // re-running the search.
    private func refreshSearchStates() {
        searchResults = searchResults.map { makeResult(for: $0.user) }
    }

    // MARK: - Actions

    func sendRequest(to user: User) async {
        errorMessage = nil
        do {
            try await dataService.sendFriendRequest(to: user.id)
            await load()
        } catch let error as FriendRequestError {
            errorMessage = error.localizedDescription
            await load()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func accept(_ request: PendingRequest) async {
        errorMessage = nil
        // Optimistic: the row leaves the requests section immediately.
        incomingRequests.removeAll { $0.id == request.id }

        do {
            try await dataService.acceptFriendRequest(friendshipId: request.friendship.id)
            await load()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            await load()
        }
    }

    func decline(_ request: PendingRequest) async {
        errorMessage = nil
        incomingRequests.removeAll { $0.id == request.id }

        do {
            try await dataService.removeFriendship(friendshipId: request.friendship.id)
            await load()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            await load()
        }
    }

    func removeFriend(_ user: User) async {
        guard
            let currentUserId,
            let edge = friendships.first(where: {
                $0.status == .accepted && $0.otherUserId(from: currentUserId) == user.id
            })
        else { return }

        errorMessage = nil
        friends.removeAll { $0.id == user.id }

        do {
            try await dataService.removeFriendship(friendshipId: edge.id)
            await load()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            await load()
        }
    }
}

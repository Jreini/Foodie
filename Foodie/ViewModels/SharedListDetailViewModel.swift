import Foundation
import Observation

// One shared list, kept live.
//
// This is the one screen where Realtime earns its place: a friend's addition
// appears while you're both looking at it. Everything else in the app is happy
// with pull-to-refresh.
@Observable
@MainActor
class SharedListDetailViewModel {
    let list: SharedList

    var entries: [SharedListEntry] = []
    var members: [SharedListMember] = []
    var restaurantsById: [UUID: Restaurant] = [:]
    var peopleById: [UUID: User] = [:]

    // Friends who aren't on the list yet — the candidates for inviting.
    var invitableFriends: [User] = []

    var isLoading = false
    var errorMessage: String?
    // Flashes briefly when a change arrives from someone else.
    var didReceiveLiveUpdate = false

    private let dataService: any DataServiceProtocol
    private var currentUserId: UUID?
    private var realtimeTask: Task<Void, Never>?

    init(list: SharedList, dataService: any DataServiceProtocol = DataServices.current) {
        self.list = list
        self.dataService = dataService
    }

    var isOwner: Bool {
        guard let currentUserId else { return false }
        return list.isOwned(by: currentUserId)
    }

    func restaurant(for entry: SharedListEntry) -> Restaurant? {
        restaurantsById[entry.restaurantId]
    }

    func addedByName(for entry: SharedListEntry) -> String? {
        entry.addedBy.flatMap { peopleById[$0]?.name }
    }

    // Restaurants already on the list, so the picker doesn't offer duplicates.
    var addableRestaurants: [Restaurant] {
        let taken = Set(entries.map(\.restaurantId))
        return restaurantsById.values
            .filter { !taken.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let currentUser = try await dataService.fetchCurrentUser()
            currentUserId = currentUser.id

            async let entriesTask = dataService.fetchListEntries(listId: list.id)
            async let membersTask = dataService.fetchListMembers(listId: list.id)
            async let restaurantsTask = dataService.fetchAllRestaurants()
            async let peopleTask = dataService.fetchAllUsers()
            async let friendsTask = dataService.fetchFriends(for: currentUser.id)

            entries = try await entriesTask
            members = try await membersTask

            restaurantsById = Dictionary(
                try await restaurantsTask.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            peopleById = Dictionary(
                try await peopleTask.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let memberIds = Set(members.map(\.userId))
            invitableFriends = try await friendsTask
                .filter { !memberIds.contains($0.id) }
                .sorted { $0.name < $1.name }
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    // MARK: - Realtime

    func startWatching() {
        guard realtimeTask == nil else { return }

        realtimeTask = Task { [weak self] in
            guard let self else { return }

            for await _ in dataService.listEntriesChanged(listId: list.id) {
                guard !Task.isCancelled else { return }

                // Refetch rather than patch: the payload could be an insert,
                // an update, or a delete, and one small query handles all three
                // without three decode paths that can drift apart.
                await reloadEntries()

                didReceiveLiveUpdate = true
                try? await Task.sleep(for: .seconds(2))
                didReceiveLiveUpdate = false
            }
        }
    }

    func stopWatching() {
        realtimeTask?.cancel()
        realtimeTask = nil
    }

    private func reloadEntries() async {
        guard let refreshed = try? await dataService.fetchListEntries(listId: list.id) else {
            return
        }
        entries = refreshed
    }

    // MARK: - Entries

    func addRestaurant(_ restaurant: Restaurant, notes: String) async {
        errorMessage = nil
        do {
            let entry = try await dataService.addListEntry(
                listId: list.id,
                restaurantId: restaurant.id,
                notes: notes
            )
            // Realtime will also deliver this back to us; inserting now keeps
            // the UI immediate, and the id match stops it appearing twice.
            if !entries.contains(where: { $0.id == entry.id }) {
                entries.insert(entry, at: 0)
            }
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func removeEntry(_ entry: SharedListEntry) async {
        errorMessage = nil
        entries.removeAll { $0.id == entry.id }

        do {
            try await dataService.removeListEntry(entryId: entry.id)
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            await reloadEntries()
        }
    }

    // MARK: - Members

    func invite(_ user: User) async {
        errorMessage = nil
        do {
            try await dataService.addListMember(listId: list.id, userId: user.id)
            await load()
        } catch {
            // The INSERT policy allows only the owner, so this is what a
            // non-owner attempt looks like.
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    func removeMember(_ member: SharedListMember) async {
        errorMessage = nil
        do {
            try await dataService.removeListMember(listId: list.id, userId: member.userId)
            await load()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }
}

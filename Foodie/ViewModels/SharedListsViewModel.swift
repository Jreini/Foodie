import Foundation
import Observation

// The index of lists the signed-in user belongs to.
@Observable
@MainActor
class SharedListsViewModel {
    var lists: [SharedList] = []
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

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
            lists = try await dataService.fetchLists()
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
        }
    }

    @discardableResult
    func createList(name: String, emoji: String?) async -> SharedList? {
        errorMessage = nil
        do {
            let list = try await dataService.createList(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                emoji: emoji
            )
            lists.insert(list, at: 0)
            return list
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            return nil
        }
    }

    func deleteList(_ list: SharedList) async {
        errorMessage = nil
        lists.removeAll { $0.id == list.id }

        do {
            try await dataService.deleteList(id: list.id)
        } catch {
            errorMessage = DataLoadFailure.message(for: error)
            await load()
        }
    }
}

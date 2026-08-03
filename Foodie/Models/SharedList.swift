import Foundation

// A list several people build together — "Taco Tour", "Date Night Spots".
//
// Named SharedList rather than List to stay out of SwiftUI.List's way. Distinct
// from `TastingListEntry`, which stays a private, single-owner list: merging the
// two would be churn without changing anything a user sees.
struct SharedList: Identifiable, Hashable {
    let id: UUID
    let ownerId: UUID
    var name: String
    var emoji: String?
    let createdAt: Date

    func isOwned(by userId: UUID) -> Bool {
        ownerId == userId
    }

    var displayEmoji: String {
        emoji.flatMap { $0.isEmpty ? nil : $0 } ?? "🍽️"
    }
}

struct SharedListEntry: Identifiable, Hashable {
    let id: UUID
    let listId: UUID
    let restaurantId: UUID
    // Nil once the person who added it deletes their account — the entry
    // survives, the attribution doesn't.
    let addedBy: UUID?
    var notes: String
    let createdAt: Date
}

struct SharedListMember: Identifiable, Hashable {
    let listId: UUID
    let userId: UUID
    let role: Role

    var id: UUID { userId }

    enum Role: String, Hashable {
        case owner
        case member
    }
}

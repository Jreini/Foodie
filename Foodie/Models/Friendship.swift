import Foundation

// One row in `friendships` — an edge between two people, with direction kept
// so a pending request knows who has to answer it.
struct Friendship: Identifiable, Hashable {
    let id: UUID
    let requesterId: UUID
    let addresseeId: UUID
    let status: Status
    let createdAt: Date

    enum Status: String, Hashable {
        case pending
        case accepted
    }

    func otherUserId(from currentUserId: UUID) -> UUID {
        requesterId == currentUserId ? addresseeId : requesterId
    }

    // Only the addressee can accept, which the database enforces too.
    func isIncomingRequest(for currentUserId: UUID) -> Bool {
        status == .pending && addresseeId == currentUserId
    }

    func isOutgoingRequest(for currentUserId: UUID) -> Bool {
        status == .pending && requesterId == currentUserId
    }
}

// How the signed-in user relates to somebody who turned up in search. Drives
// which button a search result shows.
enum FriendshipState: Hashable {
    case none
    case requestSent
    case requestReceived(friendshipId: UUID)
    case friends(friendshipId: UUID)
    case currentUser

    static func between(
        currentUserId: UUID,
        otherUserId: UUID,
        friendships: [Friendship]
    ) -> FriendshipState {
        if currentUserId == otherUserId { return .currentUser }

        guard let edge = friendships.first(where: {
            $0.otherUserId(from: currentUserId) == otherUserId
        }) else { return .none }

        switch edge.status {
        case .accepted:
            return .friends(friendshipId: edge.id)
        case .pending:
            return edge.addresseeId == currentUserId
                ? .requestReceived(friendshipId: edge.id)
                : .requestSent
        }
    }
}

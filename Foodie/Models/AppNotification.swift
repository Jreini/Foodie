import Foundation

// One row in `notifications` — something that happened to you.
//
// Named `AppNotification` rather than `Notification` because Foundation already
// owns that name for NotificationCenter, and the two would be confused in every
// file that touches both.
//
// The same rows drive both the push and the in-app inbox. A push is best-effort
// — people decline the permission, phones are off, tokens expire — so the stored
// row is the authoritative copy and the push is only a tap on the shoulder.
struct AppNotification: Identifiable, Hashable {
    let id: UUID
    // Nil when the person who caused it has since deleted their account, or for
    // a future system-authored notification with nobody behind it.
    let actor: User?
    let kind: Kind
    let listId: UUID?
    let listName: String?
    let createdAt: Date
    let readAt: Date?

    var isUnread: Bool { readAt == nil }

    // Mirrors the CHECK constraint on `notifications.type`. Decoding is
    // failable rather than defaulted: a type this build has never heard of
    // belongs to a newer version of the app, and showing it as some arbitrary
    // other kind would be worse than not showing it at all.
    enum Kind: String, Hashable {
        case friendRequest = "friend_request"
        case friendAccepted = "friend_accepted"
        case listAdded = "list_added"

        // Where this kind of notification leads. Lives on the kind rather than
        // the row because a tapped *push* has only the type string to go on —
        // the stored row may not even be loaded yet.
        var destination: PushDestination {
            switch self {
            case .friendRequest, .friendAccepted: return .friends
            case .listAdded:                      return .sharedLists
            }
        }
    }

    // MARK: - Presentation

    private var actorName: String { actor?.name ?? "Someone" }

    var message: String {
        switch kind {
        case .friendRequest:
            return "\(actorName) wants to be friends."
        case .friendAccepted:
            return "\(actorName) accepted your friend request."
        case .listAdded:
            return "\(actorName) added you to \(listName ?? "a shared list")."
        }
    }

    // Deliberately the same wording and thresholds as `FriendActivity` — the two
    // appear one tap apart, and "5m ago" next to "5 minutes ago" reads as a bug.
    var timeAgoString: String {
        let interval = Date().timeIntervalSince(createdAt)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(days)d ago"
    }

    var iconName: String {
        switch kind {
        case .friendRequest:  return "person.crop.circle.badge.plus"
        case .friendAccepted: return "checkmark.circle.fill"
        case .listAdded:      return "list.bullet.rectangle"
        }
    }

    // Where tapping this row should land.
    var destination: PushDestination { kind.destination }
}

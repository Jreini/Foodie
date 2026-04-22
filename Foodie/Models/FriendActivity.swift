import Foundation

enum ActivityType: String, Hashable, CaseIterable {
    case review = "reviewed"
    case checkIn = "checked in at"
    case addedToTastingList = "added to tasting list"
    case liked = "liked"
}

struct FriendActivity: Identifiable, Hashable {
    let id: UUID
    let user: User
    let restaurant: Restaurant
    let activityType: ActivityType
    let timestamp: Date
    // Only present when activityType == .review
    let associatedReview: Review?

    // Display label like "reviewed" or "checked in at"
    var activityLabel: String {
        activityType.rawValue
    }

    // Relative time string (e.g. "2h ago")
    var timeAgoString: String {
        let interval = Date().timeIntervalSince(timestamp)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        return "\(days)d ago"
    }
}

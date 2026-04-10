import Foundation

struct BucketListEntry: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let restaurantId: UUID
    var dateAdded: Date
    var notes: String
}

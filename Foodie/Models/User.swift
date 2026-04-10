import Foundation

struct User: Identifiable, Hashable {
    let id: UUID
    var name: String
    var username: String
    var profileImageName: String
    var bio: String
    var joinDate: Date
    var friendIds: [UUID]

    // Computed convenience properties
    var friendCount: Int { friendIds.count }
}

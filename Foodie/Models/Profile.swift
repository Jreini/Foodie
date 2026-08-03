import Foundation

// The signed-in user's row in `public.profiles`.
//
// Distinct from `User`, which is still the mock-data model the feature views
// read from. The two converge in Phase 3 when the data layer moves to Supabase;
// until then Profile covers only what the account itself owns.
struct Profile: Identifiable, Hashable, Codable {
    let id: UUID
    // Null until onboarding claims one. Stored lowercase, which is what makes
    // the database's unique index effectively case-insensitive.
    var username: String?
    var name: String?
    var bio: String
    // Object path in the public `avatars` bucket — not a URL, despite what the
    // column used to be called. See migration 20260803000100.
    var avatarPath: String?
    var createdAt: Date

    // Column names are snake_case; the SDK's decoder does no key conversion.
    enum CodingKeys: String, CodingKey {
        case id, username, name, bio
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let username { return "@\(username)" }
        return "Foodie"
    }

    var usernameHandle: String {
        username.map { "@\($0)" } ?? ""
    }
}

// MARK: - Username Rules

// Mirrors the `profiles_username_format` check constraint. Validating here too
// means the user gets an explanation instead of a database error.
enum UsernameRule {
    static let minLength = 3
    static let maxLength = 20

    enum Problem: Equatable {
        case tooShort
        case tooLong
        case invalidCharacters

        var message: String {
            switch self {
            case .tooShort:
                return "At least \(UsernameRule.minLength) characters."
            case .tooLong:
                return "At most \(UsernameRule.maxLength) characters."
            case .invalidCharacters:
                return "Letters, numbers, and underscores only."
            }
        }
    }

    // Lowercases and strips whitespace, matching what the database will accept.
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func validate(_ raw: String) -> Problem? {
        let value = normalize(raw)
        if value.count < minLength { return .tooShort }
        if value.count > maxLength { return .tooLong }
        guard value.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") })
        else { return .invalidCharacters }
        return nil
    }
}

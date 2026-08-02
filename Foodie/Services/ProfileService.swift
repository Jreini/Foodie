import Foundation
import Supabase

// Reads and writes the signed-in user's profile row.
//
// Every call here is gated by RLS: profiles are readable by any signed-in user
// (so friend search can work) but writable only by their owner. The client
// doesn't enforce that — the database does.
enum ProfileService {

    private static let table = "profiles"

    // Returns nil when no row exists yet. A trigger creates one on signup, so
    // that should only happen if the migration hasn't been applied.
    static func fetchProfile(id: UUID) async throws -> Profile? {
        // Decoding an array rather than using .single() so "no row" comes back
        // as nil instead of throwing.
        let rows: [Profile] = try await SupabaseService.client
            .from(table)
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    // Case-insensitive by construction: usernames are stored lowercase and the
    // caller normalizes before asking.
    static func isUsernameAvailable(_ username: String) async throws -> Bool {
        let rows: [UsernameRow] = try await SupabaseService.client
            .from(table)
            .select("username")
            .eq("username", value: UsernameRule.normalize(username))
            .limit(1)
            .execute()
            .value

        return rows.isEmpty
    }

    // Claims a username for the account.
    //
    // Upsert rather than update so a missing profile row still works. Only the
    // listed columns are written, so a bio set earlier survives.
    static func claimUsername(_ username: String, userId: UUID, name: String?) async throws -> Profile {
        let payload = UsernameClaim(
            id: userId,
            username: UsernameRule.normalize(username),
            name: name
        )

        return try await SupabaseService.client
            .from(table)
            .upsert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    static func updateProfile(id: UUID, name: String?, bio: String) async throws -> Profile {
        let payload = ProfileEdit(name: name, bio: bio)

        return try await SupabaseService.client
            .from(table)
            .update(payload)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    // MARK: - Payloads

    private struct UsernameRow: Decodable {
        let username: String?
    }

    private struct UsernameClaim: Encodable {
        let id: UUID
        let username: String
        let name: String?
    }

    private struct ProfileEdit: Encodable {
        let name: String?
        let bio: String
    }
}

// MARK: - Errors

// Raised when the database rejects a username that passed client-side checks —
// almost always because someone else claimed it between the availability check
// and the write.
struct UsernameTakenError: LocalizedError {
    var errorDescription: String? {
        "That username was just taken. Try another."
    }
}

extension ProfileService {
    // PostgREST surfaces a unique-constraint violation as SQLSTATE 23505.
    static func isUniqueViolation(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }
}

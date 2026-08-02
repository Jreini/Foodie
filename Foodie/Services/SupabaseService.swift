import Foundation
import Supabase

// Central Supabase configuration and the shared client for the whole app.
//
// Security note: the publishable key below is *meant* to ship inside the app
// binary. It carries no privileges of its own — every request it makes is
// gated by Row Level Security policies on the server. The SECRET key
// (sb_secret_...) bypasses RLS entirely and must never appear in this project.
enum SupabaseService {

    // MARK: - Configuration

    // Supabase Dashboard > Project Settings > Data API > Project URL.
    // Base URL only — no trailing path. The dashboard displays the REST
    // endpoint (".../rest/v1/") right next to it; the SDK appends its own
    // service paths, so including one here breaks every request.
    static let projectURL = URL(string: "https://lwyesojyqmagpnvclobl.supabase.co")!

    // Supabase Dashboard > Project Settings > API Keys > publishable key.
    // Legacy "anon" keys still work but are being retired at the end of 2026.
    static let publishableKey = "sb_publishable_csSMpmc-IgfyqWglOVxelA_nWTMC6lZ"

    // MARK: - Shared Client

    // The SDK persists the session in the keychain and refreshes tokens on its
    // own, so a signed-in user stays signed in across app launches.
    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: publishableKey
    )

}

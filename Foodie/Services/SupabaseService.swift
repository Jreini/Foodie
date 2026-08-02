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

    // MARK: - Setup Verification
    //
    // Everything below exists to confirm Phase 0 wiring is correct and is
    // deleted once real auth lands in Phase 1.

    // False while the placeholders above are still in place.
    static var isConfigured: Bool {
        !projectURL.absoluteString.contains("YOUR_PROJECT_REF")
            && !publishableKey.contains("YOUR_KEY_HERE")
    }

    // Pings the Auth health endpoint to prove the URL and key are valid.
    // Returns a human-readable line intended for the Xcode console.
    static func healthCheck() async -> String {
        guard isConfigured else {
            return "Not configured — fill in projectURL and publishableKey in SupabaseService.swift"
        }

        var request = URLRequest(url: projectURL.appending(path: "auth/v1/health"))
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Unexpected response type from \(projectURL.host() ?? "Supabase")"
            }
            let body = String(data: data, encoding: .utf8) ?? ""

            switch http.statusCode {
            case 200:
                return "Connected to \(projectURL.host() ?? "Supabase") — \(body)"
            case 401:
                return "Reached the project but the key was rejected (401). Check publishableKey."
            default:
                return "Unexpected status \(http.statusCode) — \(body)"
            }
        } catch {
            // Most often a wrong project ref (DNS failure) or no network.
            return "Could not reach \(projectURL.absoluteString) — \(error.localizedDescription)"
        }
    }
}

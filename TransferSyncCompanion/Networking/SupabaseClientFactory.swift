import Foundation
import Supabase

enum SupabaseClientFactory {
    // Initialized once at launch; safe to access from any isolation domain.
    nonisolated(unsafe) static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: AppConstants.Supabase.url,
            supabaseKey: AppConstants.Supabase.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: URL(string: "transfersync://auth/callback"),
                    flowType: .implicit,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()
}

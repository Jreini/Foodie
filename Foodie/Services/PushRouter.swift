import Foundation
import Observation

// Where a tapped notification should take you.
//
// Kept as a value rather than a screen so both entry points — a push tapped from
// the lock screen and a row tapped in the inbox — go through the same path.
enum PushDestination: Hashable {
    case friends
    case sharedLists
}

// Carries a pending destination from wherever a notification was tapped to
// whichever screen can actually show it.
//
// A singleton because there is exactly one, and because the tap arrives at the
// `UNUserNotificationCenter` delegate — outside the view hierarchy, with no
// environment to read. `FoodieApp` also injects it, so views take it from the
// environment like everything else rather than reaching for `.shared`.
//
// Consumption is pull, not push: a destination is set here and sits until a
// screen claims it. That is what makes a notification tapped at cold launch work
// — the tab that handles it may not exist yet when the tap is delivered.
@MainActor
@Observable
final class PushRouter {
    static let shared = PushRouter()

    private(set) var destination: PushDestination?

    private init() {}

    func route(to destination: PushDestination) {
        self.destination = destination
    }

    // Reads the `type` the Edge Function puts in every payload. An unrecognised
    // one means the server is ahead of this build; opening the app to wherever
    // it already was beats guessing.
    func route(fromPushPayload userInfo: [AnyHashable: Any]) {
        guard
            let raw = userInfo["type"] as? String,
            let kind = AppNotification.Kind(rawValue: raw)
        else { return }

        route(to: kind.destination)
    }

    // Claims the pending destination if it is the one the caller can handle.
    // Returns false — and leaves it pending — otherwise, so a screen never
    // swallows a route meant for a different tab.
    func consume(_ wanted: PushDestination) -> Bool {
        guard destination == wanted else { return false }
        destination = nil
        return true
    }

    // Signing out invalidates anything still pending: it was addressed to the
    // account that just left.
    func clear() {
        destination = nil
    }
}

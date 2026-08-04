import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .feed
    @Environment(PushRouter.self) private var router

    enum Tab: String {
        case feed, discover, map, decide, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "house.fill")
                }
                .tag(Tab.feed)

            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }
                .tag(Tab.discover)

            NearbyMapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(Tab.map)

            DecisionEngineView()
                .tabItem {
                    Label("Decide", systemImage: "sparkles")
                }
                .tag(Tab.decide)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
                .tag(Tab.profile)
        }
        .tint(AppTheme.primaryColor)
        // This view only selects the tab; the stack inside it does the pushing
        // and clears the router. Both hooks are needed: `onChange` covers a
        // notification tapped while the app is open, `onAppear` covers one
        // tapped at cold launch, where the destination is already set by the
        // time this view first exists.
        .onAppear { selectTabForPendingRoute() }
        .onChange(of: router.destination) { selectTabForPendingRoute() }
        // Asks for the notification permission here rather than at launch, so
        // the prompt never appears over the login screen for an account that
        // doesn't exist yet. This view is only ever built in the `.ready` state.
        .task { await PushNotificationService.shared.start() }
    }

    private func selectTabForPendingRoute() {
        switch router.destination {
        case .friends:     selectedTab = .feed
        case .sharedLists: selectedTab = .decide
        case nil:          break
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(PushRouter.shared)
}

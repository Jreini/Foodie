import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .feed

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

            MapPlaceholderView()
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
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
}

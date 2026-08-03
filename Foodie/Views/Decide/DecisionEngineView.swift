import SwiftUI

// Where each card on this screen leads.
//
// The whole tab navigates by value, not just parts of it. A view-based
// `NavigationLink` left anywhere in the chain re-activates itself when the path
// changes underneath it, so opening a reviewer's profile from a restaurant down
// here would push the card that started the journey back on top of it.
enum DecideRoute: Hashable {
    case rollTheDice
    case discoverNewTaste
    case tastingList
    case sharedLists
}

struct DecisionEngineView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingLG) {
                    Text("Can't decide where to eat?")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, AppTheme.spacingSM)

                    // Three consolidated decision option cards
                    NavigationLink(value: DecideRoute.rollTheDice) {
                        DecisionOptionCard(
                            title: "Roll the Dice",
                            subtitle: "Random pick for just you or the whole group",
                            iconName: "dice.fill",
                            gradientColors: [Color.orange, Color.red]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: DecideRoute.discoverNewTaste) {
                        DecisionOptionCard(
                            title: "Discover a New Taste",
                            subtitle: "Somewhere new — solo or with a group",
                            iconName: "sparkles",
                            gradientColors: [Color.teal, Color.blue]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: DecideRoute.tastingList) {
                        DecisionOptionCard(
                            title: "My Tasting List",
                            subtitle: "Browse, add, and pick from your saved spots",
                            iconName: "bookmark.fill",
                            gradientColors: [Color.pink, Color.orange]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: DecideRoute.sharedLists) {
                        DecisionOptionCard(
                            title: "Shared Lists",
                            subtitle: "Build lists with friends, live",
                            iconName: "person.2.fill",
                            gradientColors: [Color.purple, Color.indigo]
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingXL)
            }
            .background(AppTheme.screenBackground)
            .navigationTitle("Decide")
            // Every destination this tab can reach, registered at the root —
            // SwiftUI keeps one per type per stack, and the screens below push
            // values without knowing what renders them.
            .navigationDestination(for: DecideRoute.self) { route in
                switch route {
                case .rollTheDice:      RollTheDiceView()
                case .discoverNewTaste: DiscoverNewTasteView()
                case .tastingList:      TastingListView()
                case .sharedLists:      SharedListsView()
                }
            }
            .navigationDestination(for: SharedList.self) { list in
                SharedListDetailView(list: list)
            }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .personProfileDestination()
        }
    }
}

// Large tappable card for each decision engine option
private struct DecisionOptionCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let gradientColors: [Color]

    var body: some View {
        HStack(spacing: AppTheme.spacingLG) {
            Image(systemName: iconName)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))

            VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(AppTheme.spacingLG)
        .cardStyle()
    }
}

#Preview {
    DecisionEngineView()
}

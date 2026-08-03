import SwiftUI

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
                    NavigationLink(destination: RollTheDiceView()) {
                        DecisionOptionCard(
                            title: "Roll the Dice",
                            subtitle: "Random pick for just you or the whole group",
                            iconName: "dice.fill",
                            gradientColors: [Color.orange, Color.red]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: DiscoverNewTasteView()) {
                        DecisionOptionCard(
                            title: "Discover a New Taste",
                            subtitle: "Somewhere new — solo or with a group",
                            iconName: "sparkles",
                            gradientColors: [Color.teal, Color.blue]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: TastingListView()) {
                        DecisionOptionCard(
                            title: "My Tasting List",
                            subtitle: "Browse, add, and pick from your saved spots",
                            iconName: "bookmark.fill",
                            gradientColors: [Color.pink, Color.orange]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: SharedListsView()) {
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
            // Registered here rather than deeper, because this is the root of
            // the tab's stack and the reviewer links inside a restaurant detail
            // screen need somewhere to land.
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

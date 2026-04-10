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

                    // Four decision option cards
                    NavigationLink(destination: PickForMeView()) {
                        DecisionOptionCard(
                            title: "Pick for Me",
                            subtitle: "Random pick from your liked places & bucket list",
                            iconName: "dice.fill",
                            gradientColors: [Color.orange, Color.red]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: PickForUsView()) {
                        DecisionOptionCard(
                            title: "Pick for Us",
                            subtitle: "Find the best overlap between you and your friends",
                            iconName: "person.2.fill",
                            gradientColors: [Color.purple, Color.indigo]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: DiscoverTogetherView()) {
                        DecisionOptionCard(
                            title: "Discover Together",
                            subtitle: "A new spot nobody in the group has tried",
                            iconName: "sparkles",
                            gradientColors: [Color.teal, Color.blue]
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: BucketListView()) {
                        DecisionOptionCard(
                            title: "My Bucket List",
                            subtitle: "Browse and pick from your saved spots",
                            iconName: "bookmark.fill",
                            gradientColors: [Color.pink, Color.orange]
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingXL)
            }
            .background(AppTheme.screenBackground)
            .navigationTitle("Decide")
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

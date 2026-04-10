import SwiftUI

struct DiscoverTogetherView: View {
    @State private var viewModel = DecisionEngineViewModel()
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var result: Restaurant? = nil
    @State private var hasSearched = false

    var body: some View {
        VStack(spacing: AppTheme.spacingLG) {
            // Friend selector
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                Text("Who's exploring?")
                    .font(.headline)
                    .padding(.horizontal, AppTheme.spacingLG)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingMD) {
                        ForEach(viewModel.friends) { friend in
                            friendChip(friend)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingLG)
                }
            }

            Divider()
                .padding(.horizontal, AppTheme.spacingLG)

            // Result
            Spacer()
            if let restaurant = result {
                discoveryResultView(restaurant)
            } else if hasSearched {
                Text("No undiscovered spots found. You've been everywhere!")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                VStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.primaryColor.opacity(0.4))

                    Text("Find a new place nobody\nin the group has tried")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()

            // Action button
            Button {
                withAnimation {
                    result = viewModel.discoverForGroup(selectedFriendIds: Array(selectedFriendIds))
                    hasSearched = true
                }
            } label: {
                Label("Discover Together", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(
                        selectedFriendIds.isEmpty
                            ? Color.gray.opacity(0.3)
                            : AppTheme.primaryColor
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
            }
            .disabled(selectedFriendIds.isEmpty)
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .background(AppTheme.screenBackground)
        .navigationTitle("Discover Together")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadData() }
    }

    // MARK: - Subviews

    private func friendChip(_ friend: User) -> some View {
        let isSelected = selectedFriendIds.contains(friend.id)
        return Button {
            if isSelected {
                selectedFriendIds.remove(friend.id)
            } else {
                selectedFriendIds.insert(friend.id)
            }
            result = nil
            hasSearched = false
        } label: {
            VStack(spacing: AppTheme.spacingXS) {
                ZStack {
                    ProfileImageView(systemName: friend.profileImageName, size: 50)
                        .opacity(isSelected ? 1.0 : 0.5)

                    if isSelected {
                        Circle()
                            .stroke(AppTheme.primaryColor, lineWidth: 3)
                            .frame(width: 54, height: 54)
                    }
                }

                Text(friend.name.components(separatedBy: " ").first ?? friend.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
        }
    }

    private func discoveryResultView(_ restaurant: Restaurant) -> some View {
        VStack(spacing: AppTheme.spacingMD) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.primaryColor)

            Text("How about...")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            Text(restaurant.name)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: AppTheme.spacingSM) {
                Text(restaurant.cuisineType)
                Text("·")
                Text(restaurant.priceLevelString)
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)

            NumericRatingView(rating: restaurant.averageRating)

            if !restaurant.tags.isEmpty {
                MoodTagRow(tags: restaurant.tags)
                    .padding(.horizontal, AppTheme.spacingXXL)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

#Preview {
    NavigationStack {
        DiscoverTogetherView()
    }
}

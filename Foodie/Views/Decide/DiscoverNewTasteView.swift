import SwiftUI

struct DiscoverNewTasteView: View {
    @State private var viewModel = DecisionEngineViewModel()
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var result: Restaurant? = nil
    @State private var hasSearched = false

    private var isSolo: Bool { selectedFriendIds.isEmpty }

    var body: some View {
        VStack(spacing: AppTheme.spacingLG) {
            // Friend selector (optional — empty means solo discovery)
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                Text("Who's exploring? (optional)")
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

            // Result area
            Spacer()
            if let restaurant = result {
                discoveryResultView(restaurant)
            } else if hasSearched {
                // Honest about both causes: you really have saved everything
                // nearby, or we couldn't get a location to search around.
                Text("Couldn't find somewhere new nearby. Check that location access is on, or try again from a different spot.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                emptyPrompt
            }
            Spacer()

            // Action button — label adapts to solo vs group mode
            Button {
                withAnimation {
                    result = viewModel.discoverNewTaste(
                        selectedFriendIds: Array(selectedFriendIds)
                    )
                    hasSearched = true
                }
            } label: {
                Label("Discover a New Taste", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(AppTheme.primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, AppTheme.spacingXL)
        }
        .background(AppTheme.screenBackground)
        .navigationTitle("Discover a New Taste")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadData() }
    }

    // MARK: - Subviews

    private var emptyPrompt: some View {
        VStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.primaryColor.opacity(0.4))

            Text(isSolo
                 ? "Find a new spot you\nhaven't tried yet"
                 : "Find a new place nobody\nin the group has tried")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

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
        DiscoverNewTasteView()
    }
}

import SwiftUI

struct RollTheDiceView: View {
    @State private var viewModel = DecisionEngineViewModel()
    @State private var selectedMode: RollMode = .solo
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var rotationAngle: Double = 0

    // Mode segmented control: roll for just me or roll for the group
    enum RollMode: String, CaseIterable, Identifiable {
        case solo = "Solo"
        case group = "With Friends"
        var id: String { rawValue }
    }

    private var canRoll: Bool {
        switch selectedMode {
        case .solo: return true
        case .group: return !selectedFriendIds.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.spacingLG) {
            modePicker

            // Friend selector is only shown for group mode
            if selectedMode == .group {
                friendSelector
                Divider()
                    .padding(.horizontal, AppTheme.spacingLG)
            }

            Spacer()

            if viewModel.isAnimatingPick {
                spinningIndicator
            } else if let restaurant = viewModel.pickedRestaurant {
                pickedRestaurantCard(restaurant)
            } else {
                emptyStatePrompt
            }

            Spacer()

            // Action button + subtitle
            VStack(spacing: AppTheme.spacingMD) {
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        rotationAngle += 360
                    }
                    performRoll()
                } label: {
                    Label(
                        viewModel.pickedRestaurant == nil ? "Roll the Dice!" : "Roll Again",
                        systemImage: "dice.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(canRoll ? AppTheme.primaryColor : Color.gray.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
                }
                .disabled(!canRoll)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, AppTheme.spacingXXL)
        }
        .background(AppTheme.screenBackground)
        .navigationTitle("Roll the Dice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadData() }
    }

    // MARK: - Subviews

    private var modePicker: some View {
        Picker("Mode", selection: $selectedMode) {
            ForEach(RollMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, AppTheme.spacingLG)
        .padding(.top, AppTheme.spacingSM)
        .onChange(of: selectedMode) { _, _ in
            // Reset prior pick so the new mode starts fresh
            viewModel.resetPick()
        }
    }

    private var friendSelector: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            Text("Who's coming?")
                .font(.headline)
                .padding(.horizontal, AppTheme.spacingLG)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingMD) {
                    ForEach(viewModel.friends) { friend in
                        FriendSelectionChip(
                            user: friend,
                            isSelected: selectedFriendIds.contains(friend.id)
                        ) {
                            toggleFriendSelection(friend.id)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
            }
        }
    }

    private var spinningIndicator: some View {
        Image(systemName: "fork.knife.circle.fill")
            .font(.system(size: 80))
            .foregroundStyle(AppTheme.primaryColor)
            .rotationEffect(.degrees(rotationAngle))
    }

    private func pickedRestaurantCard(_ restaurant: Restaurant) -> some View {
        VStack(spacing: AppTheme.spacingMD) {
            Image(systemName: restaurant.imageName)
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(AppTheme.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLG))

            Text(restaurant.name)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: AppTheme.spacingSM) {
                Text(restaurant.cuisineType)
                    .foregroundStyle(AppTheme.textSecondary)
                Text("·")
                    .foregroundStyle(AppTheme.textSecondary)
                Text(restaurant.priceLevelString)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .font(.subheadline)

            NumericRatingView(rating: restaurant.averageRating)

            if !restaurant.tags.isEmpty {
                MoodTagRow(tags: restaurant.tags)
                    .padding(.horizontal, AppTheme.spacingXXL)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var emptyStatePrompt: some View {
        VStack(spacing: AppTheme.spacingMD) {
            Image(systemName: "dice.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.primaryColor.opacity(0.5))

            Text(selectedMode == .solo
                 ? "Tap the button to get\na random pick!"
                 : "Select friends, then roll to find\na spot you'll all love")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    // MARK: - Helpers

    private var subtitleText: String {
        switch selectedMode {
        case .solo:
            return "Picks from your liked places and tasting list"
        case .group:
            return "Finds the best overlap between you and your friends"
        }
    }

    // Dispatches the correct roll animation based on current mode
    private func performRoll() {
        switch selectedMode {
        case .solo:
            viewModel.pickRandomForMe()
        case .group:
            viewModel.rollForGroup(selectedFriendIds: Array(selectedFriendIds))
        }
    }

    private func toggleFriendSelection(_ id: UUID) {
        if selectedFriendIds.contains(id) {
            selectedFriendIds.remove(id)
        } else {
            selectedFriendIds.insert(id)
        }
        // Reset prior pick when the group changes
        viewModel.resetPick()
    }
}

// Circular avatar chip with selection state for friend picker
private struct FriendSelectionChip: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppTheme.spacingXS) {
                ZStack {
                    ProfileImageView(systemName: user.profileImageName, size: 50)
                        .opacity(isSelected ? 1.0 : 0.5)

                    if isSelected {
                        Circle()
                            .stroke(AppTheme.primaryColor, lineWidth: 3)
                            .frame(width: 54, height: 54)
                    }
                }

                Text(user.name.components(separatedBy: " ").first ?? user.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RollTheDiceView()
    }
}

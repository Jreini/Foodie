import SwiftUI

struct PickForUsView: View {
    @State private var viewModel = DecisionEngineViewModel()
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var result: Restaurant? = nil
    @State private var hasSearched = false

    var body: some View {
        VStack(spacing: AppTheme.spacingLG) {
            // Friend selector
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

            Divider()
                .padding(.horizontal, AppTheme.spacingLG)

            // Result area
            if let restaurant = result {
                Spacer()
                pickedResultView(restaurant)
                Spacer()
            } else if hasSearched {
                Spacer()
                noResultView
                Spacer()
            } else {
                Spacer()
                promptView
                Spacer()
            }

            // Find button
            Button {
                result = viewModel.pickForGroup(selectedFriendIds: Array(selectedFriendIds))
                hasSearched = true
            } label: {
                Label("Find a Spot", systemImage: "person.2.fill")
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
        .navigationTitle("Pick for Us")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.loadData() }
    }

    // MARK: - Subviews

    private func pickedResultView(_ restaurant: Restaurant) -> some View {
        VStack(spacing: AppTheme.spacingMD) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("You should try...")
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
        }
        .transition(.opacity)
    }

    private var noResultView: some View {
        Text("Couldn't find an overlap. Try different friends!")
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .multilineTextAlignment(.center)
    }

    private var promptView: some View {
        VStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.primaryColor.opacity(0.4))

            Text("Select friends, then find a spot\nyou'll all love")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func toggleFriendSelection(_ id: UUID) {
        if selectedFriendIds.contains(id) {
            selectedFriendIds.remove(id)
        } else {
            selectedFriendIds.insert(id)
        }
        // Reset result when changing selection
        result = nil
        hasSearched = false
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
        PickForUsView()
    }
}

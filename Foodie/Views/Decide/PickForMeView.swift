import SwiftUI

struct PickForMeView: View {
    @State private var viewModel = DecisionEngineViewModel()
    @State private var rotationAngle: Double = 0

    var body: some View {
        VStack(spacing: AppTheme.spacingXL) {
            Spacer()

            if viewModel.isAnimatingPick {
                spinningIndicator
            } else if let restaurant = viewModel.pickedRestaurant {
                pickedRestaurantCard(restaurant)
            } else {
                emptyStatePrompt
            }

            Spacer()

            // Action buttons
            VStack(spacing: AppTheme.spacingMD) {
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        rotationAngle += 360
                    }
                    viewModel.pickRandomForMe()
                } label: {
                    Label(
                        viewModel.pickedRestaurant == nil ? "Pick for Me!" : "Try Again",
                        systemImage: "dice.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(AppTheme.primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
                }

                Text("Picks from your liked places and bucket list")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, AppTheme.spacingXXL)
        }
        .background(AppTheme.screenBackground)
        .navigationTitle("Pick for Me")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadData()
        }
    }

    // MARK: - Subviews

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

            Text("Tap the button to get\na random pick!")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        PickForMeView()
    }
}

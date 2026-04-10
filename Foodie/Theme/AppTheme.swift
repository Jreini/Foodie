import SwiftUI

// Centralized design tokens for the Foodie app
enum AppTheme {

    // MARK: - Colors

    // Warm orange/coral primary accent
    static let primaryColor = Color(red: 1.0, green: 0.45, blue: 0.25)
    // Lighter tint for backgrounds and highlights
    static let primaryLight = Color(red: 1.0, green: 0.75, blue: 0.6)
    // Deep charcoal for primary text
    static let textPrimary = Color(UIColor.label)
    // Medium gray for secondary text
    static let textSecondary = Color(UIColor.secondaryLabel)
    // Subtle card background that adapts to light/dark mode
    static let cardBackground = Color(UIColor.secondarySystemGroupedBackground)
    // Screen background
    static let screenBackground = Color(UIColor.systemGroupedBackground)
    // Star/rating gold
    static let ratingColor = Color(red: 1.0, green: 0.8, blue: 0.0)
    // Mood tag background
    static let tagBackground = Color(UIColor.tertiarySystemFill)

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // MARK: - Corner Radius

    static let cornerRadiusSM: CGFloat = 8
    static let cornerRadiusMD: CGFloat = 12
    static let cornerRadiusLG: CGFloat = 16
    static let cornerRadiusXL: CGFloat = 20

    // MARK: - Card Style

    static let cardShadowRadius: CGFloat = 4
    static let cardShadowY: CGFloat = 2
    static let cardShadowColor = Color.black.opacity(0.08)

    // MARK: - Gradient

    static let primaryGradient = LinearGradient(
        colors: [primaryColor, Color(red: 1.0, green: 0.55, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

// Applies the standard card styling (rounded corners, shadow, background)
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
            .shadow(
                color: AppTheme.cardShadowColor,
                radius: AppTheme.cardShadowRadius,
                y: AppTheme.cardShadowY
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

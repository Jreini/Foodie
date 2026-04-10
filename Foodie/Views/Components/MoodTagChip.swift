import SwiftUI

// Small rounded chip for displaying mood/vibe tags
struct MoodTagChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, AppTheme.spacingSM)
            .padding(.vertical, AppTheme.spacingXS)
            .background(AppTheme.tagBackground)
            .foregroundStyle(AppTheme.textSecondary)
            .clipShape(Capsule())
    }
}

// Horizontally scrollable row of mood tag chips
struct MoodTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingXS) {
                ForEach(tags, id: \.self) { tag in
                    MoodTagChip(label: tag)
                }
            }
        }
    }
}

#Preview {
    MoodTagRow(tags: ["romantic", "date night", "cozy", "wine bar"])
        .padding()
}

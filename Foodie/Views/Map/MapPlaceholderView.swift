import SwiftUI

struct MapPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacingXL) {
                Spacer()

                // Map icon
                Image(systemName: "map.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.primaryColor.opacity(0.6))

                VStack(spacing: AppTheme.spacingSM) {
                    Text("Map Coming Soon")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("See where your friends are eating,\ndiscover hotspots, and explore what's\nbuzzing near you.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Skeleton preview of what the map will look like
                mapSkeletonPreview

                Spacer()
            }
            .padding(AppTheme.spacingLG)
            .background(AppTheme.screenBackground)
            .navigationTitle("Map")
        }
    }

    // Skeleton mockup showing where map elements will appear
    private var mapSkeletonPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusLG)
                .fill(AppTheme.tagBackground)
                .frame(height: 200)

            VStack(spacing: AppTheme.spacingMD) {
                // Fake pin markers
                HStack(spacing: AppTheme.spacingXXL) {
                    skeletonPin
                    skeletonPin
                    skeletonPin
                }

                HStack(spacing: AppTheme.spacingXL) {
                    skeletonPin
                    skeletonPin
                }

                Text("Friend pins & hotspots")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, AppTheme.spacingLG)
    }

    private var skeletonPin: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.title3)
            .foregroundStyle(AppTheme.primaryColor.opacity(0.4))
    }
}

#Preview {
    MapPlaceholderView()
}

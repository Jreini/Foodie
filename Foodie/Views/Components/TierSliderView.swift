import SwiftUI

// Interactive slider for placing a restaurant on the continuous tier spectrum
// (Fast Food -> Fine Dining). Supports an optional "average tier" marker so
// users can see where the crowd has placed this restaurant.
struct TierSliderView: View {
    @Binding var tier: RestaurantTier
    // Optional crowd-average marker (drawn as a subtle pin below the track)
    var averageTier: RestaurantTier?

    // Track height and thumb size constants for layout math
    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            // Current label updates live as the user drags
            HStack {
                Text("Tier")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text(tier.descriptiveLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(tier.zone.accentColor)
            }

            // The slider itself: GeometryReader so we can convert touches to [0,1]
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Rainbow gradient track reflecting the 5 zones
                    RoundedRectangle(cornerRadius: trackHeight / 2)
                        .fill(trackGradient)
                        .frame(height: trackHeight)

                    // Crowd-average marker (if provided)
                    if let avg = averageTier {
                        averageMarker
                            .offset(x: max(0, min(width, width * avg.value)) - 1)
                    }

                    // Draggable thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(
                            Circle().stroke(tier.zone.accentColor, lineWidth: 3)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .offset(x: thumbOffset(in: width))
                        .gesture(dragGesture(width: width))
                }
                .frame(height: thumbSize)
            }
            .frame(height: thumbSize)

            // Endpoint labels
            HStack {
                Text("Fast Food")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("Casual")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Text("Fine Dining")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    // MARK: - Subviews

    // Small vertical marker representing the crowd's average tier placement
    private var averageMarker: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppTheme.textSecondary)
                .frame(width: 2, height: trackHeight + 8)
        }
        .frame(height: thumbSize, alignment: .center)
    }

    // Gradient across all five zones in order
    private var trackGradient: LinearGradient {
        LinearGradient(
            colors: RestaurantTier.Zone.allCases.map { $0.accentColor.opacity(0.55) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Gesture + Layout Math

    // Convert the current tier value to a thumb x-offset, accounting for the
    // thumb's width so it never visually overflows the track edges.
    private func thumbOffset(in width: CGFloat) -> CGFloat {
        let usable = max(0, width - thumbSize)
        return usable * CGFloat(tier.value)
    }

    // Drag gesture maps touch x-position back into a [0, 1] tier value
    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let usable = max(1, width - thumbSize)
                let clamped = min(max(value.location.x - thumbSize / 2, 0), usable)
                tier = RestaurantTier(Double(clamped / usable))
            }
    }
}

#Preview {
    struct PreviewHarness: View {
        @State var tier = RestaurantTier(0.3)
        var body: some View {
            TierSliderView(tier: $tier, averageTier: RestaurantTier(0.55))
                .padding()
        }
    }
    return PreviewHarness()
}

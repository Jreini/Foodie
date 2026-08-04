import SwiftUI
import UIKit

// "Move and Scale" for a profile picture: pan and pinch a photo inside the
// circle it will actually be shown in, and crop to that on the way out.
//
// Before this, a picked photo went straight to upload and every avatar was
// centre-cropped at display time by `scaledToFill` — so a picture of two people,
// or one where the subject stands off to a side, lost whoever mattered. The
// crop is decided here and baked in, which also means the person choosing the
// photo is the one who decides what it shows.
//
// The result is a square, not a circle. Avatars are uploaded as JPEG, which has
// no alpha, and every place the app draws one already clips it to a `Circle()` —
// baking a circle in would just mean a black box behind it on the first screen
// that forgets to.
struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    // Zoom is relative to the smallest size that still covers the circle, so 1
    // means "as far out as it goes" and the photo can never be pulled far
    // enough back to leave a gap in the crop.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    // What the last gesture ended on. A pinch reports magnification relative to
    // its own start, so without these each new pinch would snap back to 1×.
    @State private var committedZoom: CGFloat = 1
    @State private var committedOffset: CGSize = .zero

    private let maxZoom: CGFloat = 6

    // Enough to survive the 512px downscale on upload with room to spare, and
    // capped so a hard zoom into a small photo doesn't get blown up on the way
    // out — an upscaled crop is bigger, not better.
    private let maxOutputSide: CGFloat = 1024
    private let minOutputSide: CGFloat = 256

    var body: some View {
        GeometryReader { proxy in
            let diameter = cropDiameter(in: proxy.size)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                photo(diameter: diameter)
                    .ignoresSafeArea()

                dimming(diameter: diameter)
                    .ignoresSafeArea()

                controls(diameter: diameter)
            }
            // The whole screen drives the photo, not just the circle: dragging
            // the dimmed part is how you pull a face into frame.
            .contentShape(Rectangle())
            .gesture(magnify(diameter: diameter, in: proxy.size))
            .gesture(pan(diameter: diameter))
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }

    // MARK: - Layout

    // The circle is the app's, not the photo's: it's the same shape every
    // avatar is drawn in, just bigger.
    private func cropDiameter(in size: CGSize) -> CGFloat {
        max(min(size.width, size.height) - AppTheme.spacingXXL * 2, 120)
    }

    // The scale at which the photo's shorter edge exactly spans the circle.
    // Anything at or above it covers the crop in both directions, which is what
    // makes "you can't zoom out past 1" the only constraint needed.
    private func baseScale(diameter: CGFloat) -> CGFloat {
        let shortEdge = max(min(image.size.width, image.size.height), 1)
        return diameter / shortEdge
    }

    private func displaySize(diameter: CGFloat, zoom: CGFloat) -> CGSize {
        let scale = baseScale(diameter: diameter) * zoom
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    // MARK: - Layers

    private func photo(diameter: CGFloat) -> some View {
        let size = displaySize(diameter: diameter, zoom: zoom)
        return Image(uiImage: image)
            .resizable()
            // Sized rather than scaled: the crop maths reads this same number
            // back, and a `scaleEffect` would leave the layout size saying
            // something different from what's on screen.
            .frame(width: size.width, height: size.height)
            .offset(offset)
    }

    // Everything outside the circle, dimmed. The circle is punched out of the
    // dimming rather than drawn over the photo, so what's inside it is exactly
    // the pixels that will be kept.
    private func dimming(diameter: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .mask {
                    Rectangle()
                        .overlay {
                            Circle()
                                .frame(width: diameter, height: diameter)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }

            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: diameter, height: diameter)
        }
        .allowsHitTesting(false)
    }

    private func controls(diameter: CGFloat) -> some View {
        VStack {
            Text("Move and Scale")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.top, AppTheme.spacingLG)

            Spacer()

            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white)

                Spacer()

                Button("Choose") {
                    onConfirm(croppedImage(diameter: diameter))
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.primaryColor)
            }
            .font(.body)
            .padding(.horizontal, AppTheme.spacingXL)
            .padding(.bottom, AppTheme.spacingLG)
        }
    }

    // MARK: - Gestures

    private func magnify(diameter: CGFloat, in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = min(max(committedZoom * value.magnification, 1), maxZoom)
                let anchored = anchoredOffset(
                    pinchedAt: value.startLocation,
                    in: size,
                    from: committedZoom,
                    to: newZoom,
                    offset: committedOffset
                )
                zoom = newZoom
                offset = clamped(anchored, diameter: diameter, zoom: newZoom)
            }
            .onEnded { _ in
                committedZoom = zoom
                committedOffset = offset
            }
    }

    private func pan(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clamped(proposed, diameter: diameter, zoom: zoom)
            }
            .onEnded { _ in committedOffset = offset }
    }

    // The photo may never be moved far enough for the circle to reach past its
    // edge — an avatar with a bite taken out of it isn't a crop the user should
    // be able to choose. Unlike the photo viewer's clamp this one is exact,
    // because here the displayed size is a number we set rather than whatever
    // `scaledToFit` decided.
    private func clamped(_ offset: CGSize, diameter: CGFloat, zoom: CGFloat) -> CGSize {
        let size = displaySize(diameter: diameter, zoom: zoom)
        let limitX = max((size.width - diameter) / 2, 0)
        let limitY = max((size.height - diameter) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }

    // MARK: - Cropping

    // Redraws the photo into a square the size of the circle, positioned so the
    // same pixels land in it. `UIImage.draw(in:)` is used rather than
    // `CGImage.cropping(to:)` on purpose: a photo out of the library carries an
    // orientation flag, and cropping the raw CGImage ignores it — which crops a
    // portrait photo as though it were landscape.
    private func croppedImage(diameter: CGFloat) -> UIImage {
        let display = displaySize(diameter: diameter, zoom: zoom)

        // Where the circle sits over the photo, measured from the photo's own
        // top-left corner in view points.
        let cropOrigin = CGPoint(
            x: (display.width - diameter) / 2 - offset.width,
            y: (display.height - diameter) / 2 - offset.height
        )

        // How much of the source the circle actually covers, so the output is
        // sized to the pixels that exist rather than to a fixed ideal.
        let sourcePixels = diameter / (baseScale(diameter: diameter) * zoom) * image.scale
        let outputSide = min(max(sourcePixels, minOutputSide), maxOutputSide).rounded()

        let format = UIGraphicsImageRendererFormat.default()
        // Points are pixels here — the size below is already in pixels, and a
        // 3× device would otherwise render a 3072px avatar.
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide),
            format: format
        )

        // One conversion from view points to output pixels, applied to both the
        // photo's size and its position.
        let toOutput = outputSide / diameter

        return renderer.image { _ in
            image.draw(in: CGRect(
                x: -cropOrigin.x * toOutput,
                y: -cropOrigin.y * toOutput,
                width: display.width * toOutput,
                height: display.height * toOutput
            ))
        }
    }
}

#Preview {
    // A plain colour has no interesting crop, but it does show the chrome and
    // the circle — and previews have no photo library to pull from.
    AvatarCropView(
        image: UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
        },
        onCancel: {},
        onConfirm: { _ in }
    )
}

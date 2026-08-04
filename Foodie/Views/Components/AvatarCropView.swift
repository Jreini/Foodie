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
        // The safe area is ignored out here rather than layer by layer, and
        // that placement is load-bearing. Ignoring it inside meant the photo
        // and the circle were centred on the screen while the gesture reported
        // positions inside the safe area — and since the top inset is bigger
        // than the bottom one, the centre the pinch was measured from sat about
        // a dozen points below the centre it was drawn around. Zooming drifted.
        // One container, one centre, everything agrees.
        GeometryReader { proxy in
            let diameter = cropDiameter(in: proxy.size)

            ZStack {
                Color.black

                photo(diameter: diameter, in: proxy.size)

                dimming(diameter: diameter)

                controls(diameter: diameter, insets: proxy.safeAreaInsets)
            }
            // The whole screen drives the photo, not just the circle: dragging
            // the dimmed part is how you pull a face into frame.
            .contentShape(Rectangle())
            .gesture(magnify(diameter: diameter, in: proxy.size))
            .gesture(pan(diameter: diameter))
        }
        .background(Color.black)
        .ignoresSafeArea()
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

    // Laid out at the zoom the last gesture settled on, and transformed for
    // whatever the current one is doing on top of that.
    //
    // Resizing the frame live instead would re-run layout and re-sample a
    // multi-megapixel bitmap on every frame of a pinch, which is exactly the
    // work that makes a gesture feel like it's dragging behind the finger. A
    // `scaleEffect` is a transform the GPU applies to what's already there.
    // Committing the frame at the end of the gesture is what keeps it sharp —
    // the same bargain a UIScrollView makes when it zooms.
    private func photo(diameter: CGFloat, in container: CGSize) -> some View {
        let settled = displaySize(diameter: diameter, zoom: committedZoom)
        return Image(uiImage: image)
            .resizable()
            .frame(width: settled.width, height: settled.height)
            .scaleEffect(zoom / committedZoom)
            .offset(offset)
            // The photo is deliberately larger than the screen, and a ZStack
            // sizes itself to its biggest child — so without this the stack grew
            // with the photo and quietly re-centred everything else in it. That
            // is what walked the crop circle away from the middle while zooming.
            // Pinning this layer to the container makes the photo overflow
            // visually, which it should, without moving anything.
            .frame(width: container.width, height: container.height)
    }

    // Everything outside the circle, dimmed. The circle is punched out of the
    // dimming rather than drawn over the photo, so what's inside it is exactly
    // the pixels that will be kept.
    private func dimming(diameter: CGFloat) -> some View {
        ZStack {
            // One filled path with an even-odd rule, rather than masking with
            // `.blendMode(.destinationOut)`: the blend needs an offscreen
            // buffer for the full screen, and it was being composited again on
            // every frame of every drag.
            CircleCutout(diameter: diameter)
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))

            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: diameter, height: diameter)
        }
        .allowsHitTesting(false)
    }

    // The container ignores the safe area, so the insets are applied here by
    // hand. The floors matter more than the insets do: if this ever ends up
    // somewhere the insets read as zero, the title still clears a Dynamic
    // Island and the buttons still clear the home indicator.
    private func controls(diameter: CGFloat, insets: EdgeInsets) -> some View {
        VStack {
            Text("Move and Scale")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.top, max(insets.top, 56) + AppTheme.spacingSM)

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
            .padding(.bottom, max(insets.bottom, AppTheme.spacingXL) + AppTheme.spacingSM)
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

// The whole area with a circle taken out of the middle. Filled even-odd, the
// circle is the hole.
private struct CircleCutout: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        ))
        return path
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

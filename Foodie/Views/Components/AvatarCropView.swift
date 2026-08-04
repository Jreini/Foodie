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
// The moving parts are a `UIScrollView` (`ZoomableImageScrollView`), which is
// where the responsiveness comes from and which also does the hard part of the
// arithmetic: its content inset is set so the scrollable range ends exactly
// where the circle meets the photo's edge, so a crop that would include a gap
// simply can't be scrolled to. All this view has to do is turn the square the
// scroll view reports into an image.
//
// The result is a square, not a circle. Avatars are uploaded as JPEG, which has
// no alpha, and every place the app draws one already clips it to a `Circle()` —
// baking a circle in would just mean a black box behind it on the first screen
// that forgets to.
struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    // The part of the photo currently inside the circle, in the image's own
    // points. Reported by the scroll view when it settles, and once when it is
    // first laid out — so it is filled in long before there is anything to
    // confirm, and never written while a finger is moving.
    @State private var cropRect: CGRect?

    private let maximumZoom: CGFloat = 6

    // Enough to survive the 512px downscale on upload with room to spare, and
    // capped so a hard zoom into a small photo doesn't get blown up on the way
    // out — an upscaled crop is bigger, not better.
    private let maxOutputSide: CGFloat = 1024
    private let minOutputSide: CGFloat = 256

    var body: some View {
        // The safe area is ignored out here rather than layer by layer. Doing
        // it inside meant the photo and the circle were centred on the screen
        // while the geometry was measured inside the safe area — and since the
        // top inset is bigger than the bottom, those are not the same centre.
        GeometryReader { proxy in
            let diameter = cropDiameter(in: proxy.size)

            ZStack {
                Color.black

                ZoomableImageScrollView(
                    image: image,
                    layout: .coverSquare(diameter),
                    maximumZoom: maximumZoom,
                    onCropRectChanged: { cropRect = $0 }
                )

                dimming(diameter: diameter)

                controls(insets: proxy.safeAreaInsets)
            }
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

    // MARK: - Layers

    // Everything outside the circle, dimmed. The circle is punched out of the
    // dimming rather than drawn over the photo, so what's inside it is exactly
    // the pixels that will be kept.
    private func dimming(diameter: CGFloat) -> some View {
        ZStack {
            // One filled path with an even-odd rule rather than a mask with
            // `.blendMode(.destinationOut)`, which needs a full-screen
            // offscreen buffer to composite.
            CircleCutout(diameter: diameter)
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))

            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: diameter, height: diameter)
        }
        // Hit testing off, or this would swallow every drag before the scroll
        // view underneath ever saw it.
        .allowsHitTesting(false)
    }

    // The container ignores the safe area, so the insets are applied here by
    // hand. The floors matter more than the insets do: if this ever ends up
    // somewhere the insets read as zero, the title still clears a Dynamic
    // Island and the buttons still clear the home indicator.
    private func controls(insets: EdgeInsets) -> some View {
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
                    onConfirm(croppedImage(cropRect: cropRect ?? untouchedCropRect))
                }
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.primaryColor)
            }
            .font(.body)
            .padding(.horizontal, AppTheme.spacingXL)
            .padding(.bottom, max(insets.bottom, AppTheme.spacingXL) + AppTheme.spacingSM)
        }
    }

    // MARK: - Cropping

    // What the circle frames before anything is moved: the largest centred
    // square. The scroll view reports the same thing once it has been laid
    // out, so this only stands in for the moment before that — but it means
    // Choose is never a button that does nothing.
    private var untouchedCropRect: CGRect {
        let side = min(image.size.width, image.size.height)
        return CGRect(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2,
            width: side,
            height: side
        )
    }

    // Redraws the photo into a square, positioned so the part that was inside
    // the circle is the part that lands in it. `UIImage.draw(in:)` rather than
    // `CGImage.cropping(to:)` on purpose: a photo out of the library carries an
    // orientation flag, and cropping the raw CGImage ignores it — which crops a
    // portrait photo as though it were landscape.
    private func croppedImage(cropRect: CGRect) -> UIImage {
        // Sized to the source pixels the circle actually covers, so a hard zoom
        // produces a smaller true-resolution crop rather than an upscaled one.
        let sourcePixels = cropRect.width * image.scale
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

        // One conversion from the image's points to output pixels, applied to
        // both the photo's size and its position.
        let toOutput = outputSide / max(cropRect.width, 1)

        return renderer.image { _ in
            image.draw(in: CGRect(
                x: -cropRect.minX * toOutput,
                y: -cropRect.minY * toOutput,
                width: image.size.width * toOutput,
                height: image.size.height * toOutput
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

import SwiftUI

// What to show full screen, and which image to open on.
//
// It carries the whole set rather than a single image because the tapped photo
// is rarely the only one — a review with four photos should page between them
// rather than being reopened four times. `Identifiable` so it can drive
// `.fullScreenCover(item:)`, which keeps "tap opens the viewer" down to one
// line at each call site.
struct ImageViewerSource: Identifiable {
    let urls: [URL]
    let startIndex: Int

    // Identity is the content plus the starting page, so tapping the third
    // photo after closing the first presents a fresh viewer instead of
    // reusing the old one at the wrong page.
    var id: String {
        "\(startIndex)|" + urls.map(\.absoluteString).joined(separator: "|")
    }

    // One image, the avatar case.
    init(_ url: URL) {
        self.urls = [url]
        self.startIndex = 0
    }

    // Fails on an empty set rather than presenting an empty viewer: callers
    // hand over `compactMap`ped URLs, and a review whose paths all failed to
    // resolve should do nothing at all when tapped.
    init?(urls: [URL], startIndex: Int) {
        guard !urls.isEmpty else { return nil }
        self.urls = urls
        self.startIndex = min(max(startIndex, 0), urls.count - 1)
    }
}

// A full-screen photo viewer: pinch and double-tap to zoom, drag down to
// dismiss, swipe between the photos on a review.
//
// Presented with `.fullScreenCover(item:)`, never pushed. A photo is a detour,
// not a destination — it shouldn't join the navigation stack or leave a Back
// button pointing at the screen behind it.
//
// Nothing here costs extra egress. Review photos are stored at 1600px and
// avatars at 512px, so the same URL the thumbnail already fetched is the one
// shown here, and URLSession's cache answers the second request.
struct FullScreenImageView: View {
    let source: ImageViewerSource

    @Environment(\.dismiss) private var dismiss

    // The page the pager has settled on. Optional because that is the shape
    // `scrollPosition(id:)` binds to; seeded with the tapped photo so the
    // viewer opens on the one that was actually tapped.
    @State private var currentIndex: Int?
    // Lives here rather than inside the page, because two things outside the
    // image need to know: the pager must stop swiping between photos while one
    // is zoomed, and drag-to-dismiss has to get out of panning's way.
    @State private var isZoomed = false
    @State private var dismissOffset: CGFloat = 0

    // Far enough that it can't be reached while flicking between photos.
    private let dismissThreshold: CGFloat = 120

    init(source: ImageViewerSource) {
        self.source = source
        _currentIndex = State(initialValue: source.startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            pager
                .offset(y: dismissOffset)
                // The photo shrinks and fades as it's dragged, so a drag that
                // isn't far enough to dismiss still reads as "this closes".
                .scaleEffect(photoScale)
                .opacity(photoOpacity)
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .bottom) { pageIndicator }
        .statusBarHidden()
        // The viewer is black whatever the app is set to, so materials and
        // controls need to be told that themselves.
        .environment(\.colorScheme, .dark)
        // Simultaneous so the pager keeps its horizontal swipe — the gesture
        // ignores anything more sideways than vertical. Off entirely while
        // zoomed, where a drag means panning the image instead.
        .simultaneousGesture(dismissDrag, isEnabled: !isZoomed)
    }

    // MARK: - Pages

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(source.urls.enumerated()), id: \.offset) { index, url in
                    ZoomablePage(url: url, isZoomed: $isZoomed)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentIndex)
        .scrollIndicators(.hidden)
        // A single photo has nowhere to page to, and a zoomed one is being
        // panned rather than swiped.
        .scrollDisabled(isZoomed || source.urls.count == 1)
        // Full-bleed: a photo inset by the safe area on a black screen just
        // looks like it failed to fill it. The chrome above is overlaid on the
        // ZStack instead, so it keeps its insets.
        .ignoresSafeArea()
    }

    // MARK: - Chrome

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(AppTheme.spacingMD)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(AppTheme.spacingLG)
        .accessibilityLabel("Close")
    }

    // Dots would be smaller and vaguer. With four photos, "2 of 4" says both
    // where you are and how much is left.
    @ViewBuilder
    private var pageIndicator: some View {
        if source.urls.count > 1 {
            Text("\((currentIndex ?? source.startIndex) + 1) of \(source.urls.count)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.spacingMD)
                .padding(.vertical, AppTheme.spacingXS)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, AppTheme.spacingXL)
                .opacity(chromeOpacity)
        }
    }

    // MARK: - Drag to dismiss

    private var dragProgress: CGFloat {
        min(abs(dismissOffset) / 300, 1)
    }

    private var photoScale: CGFloat {
        1 - dragProgress * 0.12
    }

    // Converted rather than left as arithmetic at the call site: `dragProgress`
    // is a CGFloat and `opacity` takes a Double, and with a literal in the
    // middle the compiler can read `1 - dragProgress * 0.5` two ways and
    // refuses to pick.
    private var photoOpacity: Double {
        1 - Double(dragProgress) * 0.5
    }

    private var chromeOpacity: Double {
        1 - Double(dragProgress)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // A sideways drag belongs to the pager, not to us. Checked on
                // every change rather than once at the start, so a swipe that
                // curves downward doesn't start closing the viewer.
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                if abs(value.translation.height) > dismissThreshold {
                    dismiss()
                } else {
                    withAnimation(.snappy) { dismissOffset = 0 }
                }
            }
    }
}

// MARK: - One page

// A single zoomable, pannable photo.
//
// Zoom state is per page: paging away from a photo and coming back should show
// it fitted again, not still magnified on the corner you left it at.
private struct ZoomablePage: View {
    let url: URL
    // Written on the way up so the pager can lock its swipe while this page is
    // zoomed in.
    @Binding var isZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    // The values the last gesture ended on. A pinch reports magnification
    // relative to its own start, so without these every new pinch would jump
    // back to 1×.
    @State private var committedScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero

    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            // Color.clear rather than gestures on the image itself: a photo is
            // letterboxed inside the page, and pinching the black beside it
            // should still zoom.
            ZStack {
                Color.clear
                image(in: proxy.size)
            }
            .contentShape(Rectangle())
            .gesture(magnify(in: proxy.size))
            // Panning exists only while zoomed. Left attached the rest of the
            // time it would swallow the pager's swipe and drag-to-dismiss.
            .gesture(pan(in: proxy.size), isEnabled: committedScale > 1)
            .onTapGesture(count: 2) { location in
                toggleZoom(toward: location, in: proxy.size)
            }
        }
        // Belt and braces for the LazyHStack, which may keep a neighbouring
        // page alive off-screen.
        .onDisappear { resetZoom() }
    }

    @ViewBuilder
    private func image(in size: CGSize) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            case .failure:
                unavailable
            default:
                // Unlike the thumbnails, a full-screen photo is worth a
                // spinner — it's the only thing on screen, and there's nothing
                // else to look at while it loads.
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Photo")
    }

    private var unavailable: some View {
        VStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "photo")
                .font(.largeTitle)
            Text("Couldn't load this photo")
                .font(.subheadline)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: - Gestures

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = min(max(committedScale * value.magnification, 1), maxScale)
                // Zoom around the pinch rather than the middle of the photo, so
                // pinching the corner of a plate brings the plate closer
                // instead of the centre of the table. Same behaviour as the
                // double tap, which has always aimed at where it was tapped.
                let anchored = anchoredOffset(
                    pinchedAt: value.startLocation,
                    in: size,
                    from: committedScale,
                    to: newScale,
                    offset: committedOffset
                )
                scale = newScale
                offset = clamped(anchored, at: newScale, in: size)
            }
            .onEnded { _ in
                if scale <= 1 {
                    withAnimation(.snappy(duration: 0.2)) { resetZoom() }
                } else {
                    committedScale = scale
                    committedOffset = offset
                    isZoomed = true
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
                offset = clamped(proposed, at: scale, in: size)
            }
            .onEnded { _ in committedOffset = offset }
    }

    // Zooms toward the tap rather than the middle, so double-tapping the plate
    // in the corner of a photo brings the plate in, not the centre of the
    // table. `scaleEffect` anchors at the centre and `offset` is applied after
    // it, so a point v away from the centre lands at scale * v — putting it in
    // the middle means offsetting by exactly that, then clamping.
    private func toggleZoom(toward point: CGPoint, in size: CGSize) {
        withAnimation(.snappy(duration: 0.25)) {
            if committedScale > 1 {
                resetZoom()
            } else {
                let fromCentre = CGSize(
                    width: point.x - size.width / 2,
                    height: point.y - size.height / 2
                )
                scale = doubleTapScale
                offset = clamped(
                    CGSize(width: -doubleTapScale * fromCentre.width,
                           height: -doubleTapScale * fromCentre.height),
                    at: doubleTapScale,
                    in: size
                )
                committedScale = scale
                committedOffset = offset
                isZoomed = true
            }
        }
    }

    private func resetZoom() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
        isZoomed = false
    }

    // Keeps a zoomed photo from being dragged off into the dark.
    //
    // Measured against the page rather than the photo, because `scaledToFit`
    // letterboxes and AsyncImage never hands back the size it settled on. The
    // cost is that a tall photo on a wide screen can travel a little past its
    // own edge; the alternative is decoding the image twice to find out how
    // big it is.
    private func clamped(_ offset: CGSize, at scale: CGFloat, in size: CGSize) -> CGSize {
        let limitX = max(size.width * (scale - 1) / 2, 0)
        let limitY = max(size.height * (scale - 1) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }
}

// Offline — in a preview or on a plane — this shows the unavailable state,
// which is the half worth being able to look at without a network.
#Preview {
    FullScreenImageView(
        source: ImageViewerSource(
            urls: [
                URL(string: "https://example.invalid/one.jpg")!,
                URL(string: "https://example.invalid/two.jpg")!
            ],
            startIndex: 0
        )!
    )
}

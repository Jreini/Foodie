import SwiftUI
import UIKit

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

            content
                .offset(y: dismissOffset)
                // The photo shrinks as it's dragged, so a drag that isn't far
                // enough to dismiss still reads as "this closes".
                .scaleEffect(photoScale)

            // The other half of that: dimming toward the black behind, rather
            // than fading the photo itself. `.opacity` on a view this size
            // forces an offscreen buffer that is recomposited on every frame
            // of the drag; a flat colour on top costs nothing and looks the
            // same against a black background.
            Color.black
                .opacity(dragDimming)
                .ignoresSafeArea()
                .allowsHitTesting(false)
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

    // A single photo skips the pager entirely rather than being a one-page
    // scroll view inside another scroll view. Every avatar and most reviews
    // take this path, and it keeps the common case free of any nested
    // scrolling for a swipe to be handed between.
    @ViewBuilder
    private var content: some View {
        if source.urls.count == 1, let url = source.urls.first {
            ZoomablePage(url: url, isZoomed: $isZoomed)
                .ignoresSafeArea()
        } else {
            pager
        }
    }

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
    // middle the compiler can read `Double(dragProgress) * 0.5` two ways and
    // refuses to pick.
    private var dragDimming: Double {
        Double(dragProgress) * 0.5
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

// A single photo: loaded here, zoomed and panned by the scroll view.
//
// The bytes are fetched directly rather than through `AsyncImage` because the
// zoom needs a `UIImage` and AsyncImage only ever hands back a SwiftUI `Image`.
// It costs no extra traffic — `URLSession.shared` reads the same shared cache
// AsyncImage does, and the thumbnail that was tapped to get here has already
// filled it.
private struct ZoomablePage: View {
    let url: URL
    // Written on the way up so the pager can lock its swipe while this page is
    // zoomed in.
    @Binding var isZoomed: Bool

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImageScrollView(
                    image: image,
                    layout: .fit,
                    onZoomedChanged: { isZoomed = $0 }
                )
            } else if failed {
                unavailable
            } else {
                // Unlike the thumbnails, a full-screen photo is worth a
                // spinner — it's the only thing on screen, and there's nothing
                // else to look at while it loads.
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .task(id: url) { await load() }
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

    private func load() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let decoded = UIImage(data: data) {
                image = decoded
            } else {
                failed = true
            }
        } catch {
            // A cancelled task is this page being torn down, not a photo that
            // couldn't be loaded — saying so would flash an error on the way
            // out of the viewer.
            if !Task.isCancelled { failed = true }
        }
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

import SwiftUI
import UIKit

// A photo you can pinch and pan, backed by a UIScrollView.
//
// This is UIKit deliberately, after two attempts at doing it with SwiftUI
// gestures. Driving zoom and pan from `DragGesture`/`MagnifyGesture` means
// writing `@State` on every touch event, and every write re-runs the view body
// and re-renders the image at its magnified size. On a real device that showed
// up as a photo that didn't move *at all* while a finger was dragging and then
// jumped when it stopped — the main thread never got far enough ahead to draw
// an intermediate frame.
//
// A UIScrollView pans by moving its own bounds, which is compositing and
// nothing else, and it brings rubber-banding, momentum, correct pinch
// anchoring and double-tap zoom with it. None of that touches SwiftUI state
// while it moves: the callbacks below fire when it settles, and when the
// answer actually changes.
struct ZoomableImageScrollView: UIViewRepresentable {

    // How the photo sits when it hasn't been zoomed.
    enum Layout: Equatable {
        // The whole photo fits inside the view — the full-screen viewer.
        case fit
        // The photo covers a centred square of this side and can be moved
        // within it, never far enough to expose an edge. The avatar cropper,
        // where the square is the crop circle's bounding box.
        case coverSquare(CGFloat)
    }

    let image: UIImage
    var layout: Layout = .fit
    // A multiple of the resting scale, not an absolute one: "four times as
    // close as it starts" means the same thing whatever the photo's size.
    var maximumZoom: CGFloat = 4

    // Fired when the scroll view settles, and once when it's first laid out —
    // never while it's moving. The square the viewport currently frames, in the
    // image's own points. Only `.coverSquare` reports one.
    var onCropRectChanged: ((CGRect) -> Void)?
    // Fired only when the answer changes, so a parent can lock its paging while
    // a photo is zoomed in.
    var onZoomedChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        // The insets here are computed, not inherited — an automatic safe-area
        // adjustment would silently move the viewport off centre.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        // The cropper deliberately shows the photo outside its viewport, dimmed
        // by the layer above; the viewer has nothing to spill.
        scrollView.clipsToBounds = layout == .fit

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Photo"
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.imageView = imageView
        // Configuration waits for a real size. `makeUIView` runs before layout,
        // so the bounds here are still zero.
        scrollView.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.layoutChanged(view)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        // The struct is recreated on every parent render; the coordinator holds
        // the callbacks, so it needs the current one.
        context.coordinator.parent = self
        // Everything else is driven from layout. Re-applying zoom or offset
        // here would throw away where the user had scrolled to every time an
        // unrelated piece of state changed.
        context.coordinator.imageChanged(scrollView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // MARK: - Scroll view

    // Subclassed for one reason: `layoutSubviews` is the only place the bounds
    // are known to be real, and a representable has no other hook into it.
    final class ZoomingScrollView: UIScrollView {
        var onLayout: ((ZoomingScrollView) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageScrollView
        weak var imageView: UIImageView?

        // What the current setup was built for. Rebuilding on every layout pass
        // would reset the zoom while the user was working.
        private var configuredSize: CGSize = .zero
        private var configuredImage: UIImage?

        // Where the viewport sits inside the bounds, and how big it is. Only
        // meaningful for `.coverSquare`.
        private var viewportOrigin: CGPoint = .zero
        private var viewportSide: CGFloat = 0

        private var lastReportedZoomed = false

        init(parent: ZoomableImageScrollView) {
            self.parent = parent
        }

        // MARK: Layout

        func layoutChanged(_ scrollView: ZoomingScrollView) {
            let size = scrollView.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            guard size != configuredSize || configuredImage !== parent.image else { return }
            configure(scrollView)
        }

        func imageChanged(_ scrollView: ZoomingScrollView) {
            guard configuredImage !== parent.image else { return }
            guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            configure(scrollView)
        }

        private func configure(_ scrollView: ZoomingScrollView) {
            guard let imageView else { return }

            let bounds = scrollView.bounds.size
            let imageSize = parent.image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            // Back to 1 first: the frame and contentSize below are unzoomed
            // measurements, and setting them while a zoom is applied leaves the
            // scroll view describing a photo that isn't the one on screen.
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.zoomScale = 1

            imageView.image = parent.image
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize

            let restingScale: CGFloat
            switch parent.layout {
            case .fit:
                restingScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
                viewportOrigin = .zero
                viewportSide = 0
                scrollView.contentInset = .zero

            case .coverSquare(let side):
                let square = min(side, min(bounds.width, bounds.height))
                // `max`, not `min`: the photo has to cover the square in both
                // directions, or a crop could include a corner of nothing.
                restingScale = max(square / imageSize.width, square / imageSize.height)
                let horizontal = max((bounds.width - square) / 2, 0)
                let vertical = max((bounds.height - square) / 2, 0)
                // This inset is what stops the viewport from ever leaving the
                // photo: it makes the scrollable range end exactly where the
                // square meets the content's edge, so the clamping is the
                // scroll view's own and needs no arithmetic of ours.
                scrollView.contentInset = UIEdgeInsets(
                    top: vertical, left: horizontal, bottom: vertical, right: horizontal
                )
                viewportOrigin = CGPoint(x: horizontal, y: vertical)
                viewportSide = square
            }

            scrollView.minimumZoomScale = restingScale
            scrollView.maximumZoomScale = restingScale * parent.maximumZoom
            scrollView.zoomScale = restingScale

            switch parent.layout {
            case .fit:
                centerWithinBounds(scrollView)
            case .coverSquare:
                scrollView.contentOffset = CGPoint(
                    x: (scrollView.contentSize.width - viewportSide) / 2 - viewportOrigin.x,
                    y: (scrollView.contentSize.height - viewportSide) / 2 - viewportOrigin.y
                )
            }

            configuredSize = bounds
            configuredImage = parent.image

            report(zoomed: false)
            reportCropRect(scrollView)
        }

        // A photo that doesn't fill the view is centred with insets rather than
        // pinned to the corner. Only `.fit` can be in that position — the
        // cropper's resting scale covers its square by definition.
        private func centerWithinBounds(_ scrollView: UIScrollView) {
            guard case .fit = parent.layout else { return }
            let horizontal = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let vertical = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: vertical, left: horizontal, bottom: vertical, right: horizontal
            )
        }

        // MARK: Delegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerWithinBounds(scrollView)
            // Fires per frame, so this reports only the transition — the parent
            // re-renders when a zoom starts or ends, not while it runs.
            report(zoomed: scrollView.zoomScale > scrollView.minimumZoomScale * 1.01)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            reportCropRect(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { reportCropRect(scrollView) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportCropRect(scrollView)
        }

        // MARK: Double tap

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView, let imageView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            // Zoom to a rect around the tap rather than to a scale, which is
            // what makes a double tap land on what was tapped. The rect is in
            // the zoomed view's coordinates, and UIScrollView does the rest.
            let target = min(scrollView.minimumZoomScale * 2.5, scrollView.maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let size = CGSize(
                width: scrollView.bounds.width / target,
                height: scrollView.bounds.height / target
            )
            scrollView.zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
        }

        // MARK: Reporting

        // Both reports are deferred by a turn rather than called straight out.
        // The first of them happens during layout, and writing SwiftUI state
        // inside a view update is what "Modifying state during view update"
        // complains about. `Task` rather than `DispatchQueue`: the project
        // defaults its isolation to the main actor, so this stays on it.
        private func report(zoomed: Bool) {
            guard zoomed != lastReportedZoomed else { return }
            lastReportedZoomed = zoomed
            let notify = parent.onZoomedChanged
            Task { notify?(zoomed) }
        }

        private func reportCropRect(_ scrollView: UIScrollView) {
            guard case .coverSquare = parent.layout, let notify = parent.onCropRectChanged else { return }
            let scale = scrollView.zoomScale
            guard scale > 0, viewportSide > 0 else { return }

            // A point of content sits at `content - contentOffset` on screen,
            // and the viewport's top-left is at `viewportOrigin` — so the
            // content under it is the sum, and dividing by the zoom puts it
            // back into the image's own points.
            let side = viewportSide / scale
            let origin = CGPoint(
                x: (scrollView.contentOffset.x + viewportOrigin.x) / scale,
                y: (scrollView.contentOffset.y + viewportOrigin.y) / scale
            )

            // Bouncing can carry the viewport past the edge for a moment. It
            // always settles back, but clamping here means a crop taken mid-
            // bounce can't include a strip of nothing.
            let imageSize = parent.image.size
            let rect = CGRect(
                x: min(max(origin.x, 0), max(imageSize.width - side, 0)),
                y: min(max(origin.y, 0), max(imageSize.height - side, 0)),
                width: side,
                height: side
            )
            Task { notify(rect) }
        }
    }
}

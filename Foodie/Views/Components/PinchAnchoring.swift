import SwiftUI

// Where zoomable content has to move so that whatever is under a pinch stays
// under it while the scale changes.
//
// Both zoomable surfaces in the app need exactly this — the full-screen photo
// viewer and the avatar cropper — and getting it wrong is the difference
// between zooming in on the thing you're looking at and zooming in on the
// middle of the picture regardless.
//
// The derivation, since the four terms are otherwise unreadable: content is
// drawn at `screen = offset + scale * v`, where `v` is a point measured from
// the centre of the content. The point under the pinch is therefore
// `v = (p - offset) / scale`. Holding it in place at the new scale means
// solving `p = newOffset + newScale * v`, which is
//
//     newOffset = p - (newScale / scale) * (p - offset)
//
// `point` is in the zoomed view's own coordinate space (what a gesture's
// `startLocation` reports), so it's shifted to centre-relative first. The
// caller still has to clamp the result to its own bounds.
func anchoredOffset(
    pinchedAt point: CGPoint,
    in size: CGSize,
    from scale: CGFloat,
    to newScale: CGFloat,
    offset: CGSize
) -> CGSize {
    // A zero scale would be a divide by zero, and can't happen — every caller
    // clamps its scale to at least 1 — but the failure mode would be a NaN
    // offset that silently blanks the view rather than an obvious crash.
    guard scale > 0 else { return offset }

    let anchor = CGSize(
        width: point.x - size.width / 2,
        height: point.y - size.height / 2
    )
    let growth = newScale / scale

    return CGSize(
        width: anchor.width - growth * (anchor.width - offset.width),
        height: anchor.height - growth * (anchor.height - offset.height)
    )
}

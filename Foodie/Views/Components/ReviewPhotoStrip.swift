import SwiftUI

// The row of photos attached to a review, wherever a review is shown.
//
// It lives here rather than inside the restaurant page because the feed shows
// the same review — a photo strip that looked different depending on which
// screen you reached the review from would just be two implementations drifting
// apart.
//
// It owns the full-screen viewer as well as the thumbnails, so a call site is
// one line and can't forget the `.fullScreenCover` that makes the photos worth
// tapping. It also draws nothing when there's nothing to draw, so callers don't
// each repeat the empty check.
struct ReviewPhotoStrip: View {
    // Storage paths as they come off the review row, not URLs — resolving them
    // is this view's job so no caller has to know which bucket they're in.
    let photoNames: [String]

    @State private var viewerSource: ImageViewerSource?

    // Resolved once and used for both the row and the viewer, so the index the
    // viewer opens on always means the photo that was tapped. A path that
    // doesn't resolve to a URL is dropped from both rather than leaving a hole
    // in one of them.
    private var photoURLs: [URL] {
        photoNames.compactMap(PhotoUploadService.publicURL(for:))
    }

    var body: some View {
        if !photoURLs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSM) {
                    ForEach(Array(photoURLs.enumerated()), id: \.element) { index, url in
                        photo(url, at: index)
                    }
                }
            }
            .fullScreenCover(item: $viewerSource) { source in
                FullScreenImageView(source: source)
            }
        }
    }

    // A 120pt square is a thumbnail of a photo that was uploaded at 1600px, so
    // there's a lot more of it to see. Tapping opens the whole row, starting
    // here, rather than this one photo on its own.
    private func photo(_ url: URL, at index: Int) -> some View {
        Button {
            viewerSource = ImageViewerSource(urls: photoURLs, startIndex: index)
        } label: {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(AppTheme.textSecondary)
                default:
                    ProgressView()
                }
            }
            .frame(width: 120, height: 120)
            .background(AppTheme.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review photo \(index + 1) of \(photoURLs.count)")
        .accessibilityHint("Shows the photo full screen")
    }
}

// The paths resolve to real CDN URLs that hold nothing, so a preview shows the
// thumbnails in their failure state — the layout is the half worth looking at
// without a session.
#Preview {
    ReviewPhotoStrip(photoNames: ["preview/one.jpg", "preview/two.jpg", "preview/three.jpg"])
        .padding()
}

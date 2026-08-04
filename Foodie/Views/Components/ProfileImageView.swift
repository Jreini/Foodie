import SwiftUI

// Circular profile picture, falling back to an SF Symbol when there isn't one.
//
// Takes a storage path rather than a URL so callers can hand it a `User` or a
// `Profile` field directly and stay out of the bucket's business. The bucket is
// public, so resolving a path costs no round trip.
struct ProfileImageView: View {
    let avatarPath: String?
    var size: CGFloat = 40
    // Overridable so a "nobody in particular" slot can show something other
    // than a person, but every real profile uses the default.
    var fallbackSymbol: String = "person.circle.fill"
    // Opt-in, and off by default on purpose: most avatars in the app sit inside
    // a NavigationLink — a feed card, a friends row, the name on a review —
    // where a tap already means "open this person". Taking that tap to show a
    // 36pt picture at full size would be a bad trade. The big header avatars,
    // which link nowhere, turn it on.
    var opensFullScreen: Bool = false

    @State private var viewerSource: ImageViewerSource?

    init(
        avatarPath: String?,
        size: CGFloat = 40,
        fallbackSymbol: String = "person.circle.fill",
        opensFullScreen: Bool = false
    ) {
        self.avatarPath = avatarPath
        self.size = size
        self.fallbackSymbol = fallbackSymbol
        self.opensFullScreen = opensFullScreen
    }

    // The common case: whoever this row is about.
    init(user: User, size: CGFloat = 40, opensFullScreen: Bool = false) {
        self.init(avatarPath: user.avatarPath, size: size, opensFullScreen: opensFullScreen)
    }

    var body: some View {
        Group {
            // Only a real picture is worth opening. Someone who hasn't set one
            // has a placeholder, and a full-screen SF Symbol is a dead end.
            if opensFullScreen, let url = avatarURL {
                Button {
                    viewerSource = ImageViewerSource(url)
                } label: {
                    avatar(url: url)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile picture")
                .accessibilityHint("Shows the picture full screen")
            } else {
                avatar(url: avatarURL)
            }
        }
        .fullScreenCover(item: $viewerSource) { source in
            FullScreenImageView(source: source)
        }
    }

    private var avatarURL: URL? {
        avatarPath.flatMap(PhotoUploadService.avatarURL(for:))
    }

    @ViewBuilder
    private func avatar(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        // Both "loading" and "failed" show the placeholder. A
                        // spinner in a 28pt circle reads as breakage, and a
                        // 36pt avatar isn't worth a progress indicator.
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: fallbackSymbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(AppTheme.primaryColor)
    }
}

#Preview {
    HStack(spacing: 16) {
        ProfileImageView(avatarPath: nil, size: 32)
        ProfileImageView(avatarPath: nil, size: 50)
        ProfileImageView(avatarPath: nil, size: 80)
    }
    .padding()
}

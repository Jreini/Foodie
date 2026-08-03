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

    init(avatarPath: String?, size: CGFloat = 40, fallbackSymbol: String = "person.circle.fill") {
        self.avatarPath = avatarPath
        self.size = size
        self.fallbackSymbol = fallbackSymbol
    }

    // The common case: whoever this row is about.
    init(user: User, size: CGFloat = 40) {
        self.init(avatarPath: user.avatarPath, size: size)
    }

    var body: some View {
        Group {
            if let url = avatarPath.flatMap(PhotoUploadService.avatarURL(for:)) {
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

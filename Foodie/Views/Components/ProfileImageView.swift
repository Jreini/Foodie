import SwiftUI

// Circular profile image using SF Symbols as placeholder
struct ProfileImageView: View {
    let systemName: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(AppTheme.primaryColor)
            .clipShape(Circle())
    }
}

#Preview {
    HStack(spacing: 16) {
        ProfileImageView(systemName: "person.circle.fill", size: 32)
        ProfileImageView(systemName: "person.circle.fill", size: 50)
        ProfileImageView(systemName: "person.circle.fill", size: 80)
    }
    .padding()
}

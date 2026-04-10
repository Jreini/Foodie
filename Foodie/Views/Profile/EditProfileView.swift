import SwiftUI

struct EditProfileView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Profile image (non-editable placeholder for now)
                    HStack {
                        Spacer()
                        VStack(spacing: AppTheme.spacingSM) {
                            ProfileImageView(systemName: user.profileImageName, size: 80)

                            Text("Change Photo")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.primaryColor)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Display name", text: $name)
                }

                Section("Username") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Bio") {
                    TextEditor(text: $bio)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Will persist once database is connected
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = user.name
                username = user.username
                bio = user.bio
            }
        }
    }
}

#Preview {
    EditProfileView(user: User(
        id: UUID(), name: "Justin Reini", username: "justineats",
        profileImageName: "person.circle.fill",
        bio: "Always hunting for the best tacos.",
        joinDate: Date(), friendIds: []
    ))
}

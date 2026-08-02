import SwiftUI

// Edits the real `profiles` row. Name and bio are writable; the username is
// shown but fixed, since changing a handle friends already know is a separate
// feature with its own uniqueness and re-linking concerns.
struct EditProfileView: View {
    let profile: Profile

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Avatar upload lands with photo support in Phase 7.
                    HStack {
                        Spacer()
                        ProfileImageView(systemName: "person.circle.fill", size: 80)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Display name", text: $name)
                }

                Section {
                    HStack {
                        Text("@\(profile.username ?? "")")
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                    }
                } header: {
                    Text("Username")
                } footer: {
                    Text("Your username can't be changed right now.")
                }

                Section("Bio") {
                    TextEditor(text: $bio)
                        .frame(minHeight: 80)
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                name = profile.name ?? ""
                bio = profile.bio
            }
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try await auth.updateProfile(
                name: trimmedName.isEmpty ? nil : trimmedName,
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            saveError = "Couldn't save your profile. Please try again."
        }
    }
}

#Preview {
    EditProfileView(
        profile: Profile(
            id: UUID(),
            username: "justineats",
            name: "Justin Reini",
            bio: "Always hunting for the best tacos.",
            avatarURL: nil,
            createdAt: Date()
        )
    )
    .environment(AuthManager())
}

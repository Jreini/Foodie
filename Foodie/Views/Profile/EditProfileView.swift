import SwiftUI
import PhotosUI

// Edits the real `profiles` row. Name, bio and profile picture are writable;
// the username is shown but fixed, since changing a handle friends already know
// is a separate feature with its own uniqueness and re-linking concerns.
struct EditProfileView: View {
    let profile: Profile

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var bio: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    // Nil means "leave the picture alone". `.removed` and `.picked` are the two
    // ways it changes, and they're deliberately distinct: one writes null, the
    // other uploads first. Nothing is written until Save, so backing out of the
    // sheet leaves no orphaned upload behind.
    @State private var avatarChange: AvatarChange?
    @State private var pickerSelection: PhotosPickerItem?
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showAvatarOptions = false
    @State private var isPreparingPhoto = false

    // Every new photo goes through the cropper before it becomes the pending
    // change, whichever way it arrived.
    @State private var photoToCrop: CroppablePhoto?
    // A camera capture waits here until its own sheet has gone. Presenting the
    // cropper from inside `onCapture` puts a second full-screen cover up while
    // the first is still dismissing, and SwiftUI drops it.
    @State private var capturedPhoto: UIImage?

    // Same reason as the review composer: Return inserts a newline in a
    // TextEditor, so there's no built-in way to put the keyboard away.
    @FocusState private var isBioFocused: Bool

    private enum AvatarChange {
        case picked(UIImage)
        case removed
    }

    // `.fullScreenCover(item:)` needs an Identifiable, and a UIImage isn't one.
    // The fresh id also means picking the same photo twice still presents the
    // cropper the second time.
    private struct CroppablePhoto: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    avatarPicker
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
                        .focused($isBioFocused)
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isBioFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .confirmationDialog(
                "Profile Picture",
                isPresented: $showAvatarOptions,
                titleVisibility: .visible
            ) {
                // Offered only on hardware that has a camera — the Simulator
                // would present a dead black sheet.
                if CameraPicker.isAvailable {
                    Button("Take Photo") { showCamera = true }
                }
                Button("Choose from Library") { showPhotoLibrary = true }
                if hasAvatar {
                    Button("Remove Photo", role: .destructive) {
                        avatarChange = .removed
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(
                isPresented: $showPhotoLibrary,
                selection: $pickerSelection,
                matching: .images
            )
            .fullScreenCover(isPresented: $showCamera, onDismiss: presentCropperForCapture) {
                CameraPicker { image in
                    capturedPhoto = image
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $photoToCrop) { photo in
                AvatarCropView(
                    image: photo.image,
                    onCancel: { photoToCrop = nil },
                    onConfirm: { cropped in
                        avatarChange = .picked(cropped)
                        photoToCrop = nil
                    }
                )
            }
            .onChange(of: pickerSelection) { _, item in
                Task { await loadPickedPhoto(item) }
            }
            .onAppear {
                name = profile.name ?? ""
                bio = profile.bio
            }
        }
    }

    // MARK: - Avatar

    private var avatarPicker: some View {
        VStack(spacing: AppTheme.spacingSM) {
            Button {
                showAvatarOptions = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    avatarPreview

                    // Sits on the edge of the circle so the control reads as
                    // editable without a second row of chrome.
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.primaryColor, in: Circle())
                        .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .disabled(isPreparingPhoto)

            Text(isPreparingPhoto ? "Preparing photo…" : "Tap to change")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var avatarPreview: some View {
        switch avatarChange {
        case .picked(let image)?:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
        case .removed?:
            ProfileImageView(avatarPath: nil, size: 88)
        case nil:
            ProfileImageView(avatarPath: profile.avatarPath, size: 88)
        }
    }

    // True when there is something to remove — either the stored picture or one
    // just chosen in this sheet.
    private var hasAvatar: Bool {
        switch avatarChange {
        case .picked?: return true
        case .removed?: return false
        case nil: return profile.avatarPath != nil
        }
    }

    // PhotosPickerItem only hands over data on request, so decode after the
    // picker closes rather than blocking it.
    private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        isPreparingPhoto = true
        defer {
            isPreparingPhoto = false
            // Cleared so picking the same photo twice still fires onChange.
            pickerSelection = nil
        }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            // Bounded before it reaches the cropper: a full-resolution photo is
            // a multi-megapixel bitmap to transform on every frame of a drag,
            // and the crop is downscaled to 512px on upload regardless. Done
            // here, behind "Preparing photo…", rather than during the gesture.
            photoToCrop = CroppablePhoto(image: PhotoUploadService.editingCopy(of: image))
        } else {
            saveError = "That photo couldn't be opened. Try another."
        }
    }

    // Runs once the camera sheet is actually gone — see `capturedPhoto`.
    private func presentCropperForCapture() {
        guard let capturedPhoto else { return }
        self.capturedPhoto = nil
        photoToCrop = CroppablePhoto(image: PhotoUploadService.editingCopy(of: capturedPhoto))
    }

    // MARK: - Saving

    private func save() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await saveAvatarIfChanged()

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

    // Upload first, then point the row at it — the same order review photos
    // use, so a profile never references a file that failed to arrive.
    private func saveAvatarIfChanged() async throws {
        guard let avatarChange else { return }
        guard case .ready(let user, _) = auth.state else { return }

        let newPath: String?
        switch avatarChange {
        case .picked(let image):
            newPath = try await PhotoUploadService.uploadAvatar(image, userId: user.id)
        case .removed:
            newPath = nil
        }

        let previousPath = try await auth.updateAvatar(path: newPath)

        // Only once the row no longer points at it. Storage doesn't cascade,
        // so leaving this out would quietly accumulate a file per edit.
        if let previousPath, previousPath != newPath {
            await PhotoUploadService.removeAvatar(at: previousPath)
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
            avatarPath: nil,
            createdAt: Date()
        )
    )
    .environment(AuthManager())
}

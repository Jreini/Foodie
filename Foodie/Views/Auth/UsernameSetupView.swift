import SwiftUI

// One-time onboarding after first sign-in.
//
// Apple and Google supply a name and email but no handle, and friends find each
// other by handle — so this is the one thing the app has to ask for itself.
struct UsernameSetupView: View {
    @Environment(AuthManager.self) private var auth

    // Name from the auth provider, used only to make the greeting personal.
    let displayName: String?

    @State private var username = ""
    @State private var availability: Availability = .idle
    @State private var isSubmitting = false
    @State private var submitError: String?
    // Debounces the availability lookup so a lookup doesn't fire per keystroke.
    @State private var availabilityCheck: Task<Void, Never>?

    @FocusState private var isFieldFocused: Bool

    enum Availability: Equatable {
        case idle
        case checking
        case available
        case taken
        case invalid(UsernameRule.Problem)
        case checkFailed
    }

    var body: some View {
        ZStack {
            AppTheme.screenBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppTheme.spacingXL) {
                header
                usernameField
                Spacer()
                continueButton
            }
            .padding(AppTheme.spacingXL)
        }
        .onAppear { isFieldFocused = true }
        .onDisappear { availabilityCheck?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            Text(greeting)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Pick a username so friends can find you.")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.top, AppTheme.spacingXXL)
    }

    private var greeting: String {
        guard let displayName, !displayName.isEmpty else { return "Welcome to Foodie" }
        // Just the first name keeps the line short on narrow screens.
        let firstName = displayName.split(separator: " ").first.map(String.init) ?? displayName
        return "Welcome, \(firstName)"
    }

    // MARK: - Field

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: 2) {
                Text("@")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textSecondary)

                TextField("username", text: $username)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($isFieldFocused)
                    .submitLabel(.done)
                    .onChange(of: username) { _, newValue in
                        handleUsernameChange(newValue)
                    }

                statusIndicator
            }
            .padding(AppTheme.spacingLG)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))

            statusMessage
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch availability {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .taken, .invalid:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .idle, .checkFailed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message = submitError {
            statusText(message, color: .red)
        } else {
            switch availability {
            case .available:
                statusText("@\(UsernameRule.normalize(username)) is available.", color: .green)
            case .taken:
                statusText("That username is taken.", color: .red)
            case .invalid(let problem):
                statusText(problem.message, color: AppTheme.textSecondary)
            case .checkFailed:
                statusText("Couldn't check that name. You can still try it.", color: AppTheme.textSecondary)
            case .idle, .checking:
                // Reserves the line so the layout doesn't jump as status changes.
                statusText(" ", color: .clear)
            }
        }
    }

    private func statusText(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(color)
            .padding(.leading, AppTheme.spacingXS)
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue").fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(canSubmit ? AnyShapeStyle(AppTheme.primaryGradient)
                                  : AnyShapeStyle(Color.gray.opacity(0.3)))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMD))
        }
        .disabled(!canSubmit || isSubmitting)
    }

    // Availability is advisory — the unique index is the real gate — so a
    // failed lookup shouldn't block someone from trying.
    private var canSubmit: Bool {
        guard UsernameRule.validate(username) == nil else { return false }
        return availability == .available || availability == .checkFailed
    }

    // MARK: - Behavior

    private func handleUsernameChange(_ newValue: String) {
        submitError = nil
        availabilityCheck?.cancel()

        if let problem = UsernameRule.validate(newValue) {
            // Don't scold someone who has only typed one character yet.
            availability = newValue.isEmpty ? .idle : .invalid(problem)
            return
        }

        availability = .checking
        availabilityCheck = Task {
            // Debounce; cancellation here is normal, not an error.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            do {
                let free = try await ProfileService.isUsernameAvailable(newValue)
                guard !Task.isCancelled else { return }
                availability = free ? .available : .taken
            } catch {
                guard !Task.isCancelled else { return }
                availability = .checkFailed
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            try await auth.claimUsername(username)
            // On success the root view swaps this screen out; nothing else to do.
        } catch let error as UsernameTakenError {
            availability = .taken
            submitError = error.localizedDescription
        } catch {
            submitError = "Couldn't save that username. Please try again."
        }
    }
}

#Preview {
    UsernameSetupView(displayName: "Justin Reini")
        .environment(AuthManager())
}

import SwiftUI

// Find people, answer requests, manage friends.
//
// Reached from the friend count on Profile. Everything here writes to
// `friendships`, whose policies mean the database — not this screen — decides
// who may accept what.
struct FriendsView: View {
    @State private var viewModel = FriendsViewModel()

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section { errorRow(message) }
            }

            if viewModel.isSearching || !viewModel.searchResults.isEmpty {
                searchSection
            } else {
                if !viewModel.incomingRequests.isEmpty { incomingSection }
                if !viewModel.outgoingRequests.isEmpty { outgoingSection }
                friendsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search by username"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await viewModel.load() }
        .overlay { emptyOverlay }
        .task { await viewModel.load() }
    }

    // MARK: - Sections

    private var searchSection: some View {
        Section("Results") {
            if viewModel.isSearching && viewModel.searchResults.isEmpty {
                HStack {
                    ProgressView()
                    Text("Searching…").foregroundStyle(AppTheme.textSecondary)
                }
            } else if viewModel.searchResults.isEmpty {
                Text("No one found with that username.")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(viewModel.searchResults) { result in
                    searchRow(result)
                }
            }
        }
    }

    private var incomingSection: some View {
        Section("Requests") {
            ForEach(viewModel.incomingRequests) { request in
                HStack {
                    personLabel(request.user)
                    Spacer()

                    // Two destructive-adjacent actions side by side, so the
                    // affirmative one carries the color.
                    Button("Accept") {
                        Task { await viewModel.accept(request) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryColor)

                    Button("Decline") {
                        Task { await viewModel.decline(request) }
                    }
                    .buttonStyle(.bordered)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var outgoingSection: some View {
        Section("Sent") {
            ForEach(viewModel.outgoingRequests) { request in
                HStack {
                    personLabel(request.user)
                    Spacer()
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var friendsSection: some View {
        Section("Friends (\(viewModel.friends.count))") {
            if viewModel.friends.isEmpty {
                Text("No friends yet. Search for a username to add someone.")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(viewModel.friends) { friend in
                    personLabel(friend)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task { await viewModel.removeFriend(friend) }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Rows

    private func searchRow(_ result: FriendsViewModel.SearchResult) -> some View {
        HStack {
            personLabel(result.user)
            Spacer()
            searchAction(for: result)
        }
    }

    @ViewBuilder
    private func searchAction(for result: FriendsViewModel.SearchResult) -> some View {
        switch result.state {
        case .currentUser:
            Text("You")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

        case .friends:
            Label("Friends", systemImage: "checkmark")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

        case .requestSent:
            Text("Pending")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

        case .requestReceived:
            // They asked first — accepting is the natural action, not sending
            // a second request that the unique index would reject anyway.
            Button("Accept") {
                if let request = viewModel.incomingRequests.first(where: {
                    $0.user.id == result.user.id
                }) {
                    Task { await viewModel.accept(request) }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryColor)

        case .none:
            Button("Add") {
                Task { await viewModel.sendRequest(to: result.user) }
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.primaryColor)
        }
    }

    private func personLabel(_ user: User) -> some View {
        HStack(spacing: AppTheme.spacingMD) {
            ProfileImageView(systemName: user.profileImageName, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.textPrimary)

                if !user.username.isEmpty {
                    Text("@\(user.username)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if viewModel.isLoading
            && viewModel.friends.isEmpty
            && viewModel.incomingRequests.isEmpty {
            ProgressView()
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView()
    }
}

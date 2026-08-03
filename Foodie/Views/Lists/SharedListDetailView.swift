import SwiftUI

// A shared list, kept live while it's on screen.
struct SharedListDetailView: View {
    @State private var viewModel: SharedListDetailViewModel
    @State private var showAddSheet = false
    @State private var showMembersSheet = false

    init(list: SharedList) {
        _viewModel = State(initialValue: SharedListDetailViewModel(list: list))
    }

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(viewModel.entries) { entry in
                    entryRow(entry)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task { await viewModel.removeEntry(entry) }
                            }
                        }
                }
            } header: {
                HStack {
                    Text("\(viewModel.entries.count) place\(viewModel.entries.count == 1 ? "" : "s")")
                    Spacer()
                    if viewModel.didReceiveLiveUpdate {
                        Label("Updated", systemImage: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.primaryColor)
                            .transition(.opacity)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.2), value: viewModel.didReceiveLiveUpdate)
        .navigationTitle("\(viewModel.list.displayEmoji) \(viewModel.list.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Restaurant", systemImage: "plus")
                    }
                    Button {
                        showMembersSheet = true
                    } label: {
                        Label("Members", systemImage: "person.2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddToListSheet(
                restaurants: viewModel.addableRestaurants,
                onAdd: { restaurant, notes in
                    await viewModel.addRestaurant(restaurant, notes: notes)
                }
            )
        }
        .sheet(isPresented: $showMembersSheet) {
            ListMembersSheet(viewModel: viewModel)
        }
        .overlay { statusOverlay }
        .refreshable { await viewModel.load() }
        .task {
            await viewModel.load()
            // Subscribing after the first load means the initial rows come from
            // one query rather than trickling in as events.
            viewModel.startWatching()
        }
        .onDisappear { viewModel.stopWatching() }
    }

    private func entryRow(_ entry: SharedListEntry) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            if let restaurant = viewModel.restaurant(for: entry) {
                NavigationLink(value: restaurant) {
                    RestaurantRowView(restaurant: restaurant)
                }
            } else {
                // The restaurant row hasn't loaded (or was removed); the entry
                // is still real, so show what we have.
                Text("Unknown restaurant")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !entry.notes.isEmpty {
                Text(entry.notes)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if let name = viewModel.addedByName(for: entry) {
                Text("Added by \(name)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, AppTheme.spacingXS)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            ProgressView()
        } else if !viewModel.isLoading && viewModel.entries.isEmpty {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "fork.knife")
            } description: {
                Text("Add a restaurant and your friends will see it appear.")
            }
        }
    }
}

// MARK: - Add

private struct AddToListSheet: View {
    let restaurants: [Restaurant]
    let onAdd: (Restaurant, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Restaurant?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    Form {
                        Section("Restaurant") {
                            RestaurantRowView(restaurant: selected)
                        }
                        Section("Notes") {
                            TextField("Why this one?", text: $notes, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }
                } else {
                    List(restaurants) { restaurant in
                        Button {
                            selected = restaurant
                        } label: {
                            RestaurantRowView(restaurant: restaurant)
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay {
                        if restaurants.isEmpty {
                            ContentUnavailableView {
                                Label("Nothing to add", systemImage: "fork.knife")
                            } description: {
                                Text("Save a few places from Discover first — everything you've saved is already on this list.")
                            }
                        }
                    }
                }
            }
            .navigationTitle(selected == nil ? "Pick a Place" : "Add Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let selected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            Task {
                                await onAdd(selected, notes)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Members

private struct ListMembersSheet: View {
    // No `$` bindings needed — @Observable tracks reads through a plain let.
    let viewModel: SharedListDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Members") {
                    ForEach(viewModel.members) { member in
                        HStack {
                            Text(viewModel.peopleById[member.userId]?.name ?? "Someone")
                            Spacer()
                            Text(member.role.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .swipeActions {
                            // Only the owner can remove others, and the owner
                            // can't be removed at all.
                            if viewModel.isOwner && member.role != .owner {
                                Button("Remove", role: .destructive) {
                                    Task { await viewModel.removeMember(member) }
                                }
                            }
                        }
                    }
                }

                if viewModel.isOwner {
                    Section("Invite a friend") {
                        if viewModel.invitableFriends.isEmpty {
                            Text("All your friends are already on this list.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.textSecondary)
                        } else {
                            ForEach(viewModel.invitableFriends) { friend in
                                HStack {
                                    Text(friend.name)
                                    Spacer()
                                    Button("Add") {
                                        Task { await viewModel.invite(friend) }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(AppTheme.primaryColor)
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Only the list owner can invite people.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SharedListDetailView(
            list: SharedList(
                id: MockDataService.sampleListId,
                ownerId: MockDataService.currentUserId,
                name: "Taco Tour",
                emoji: "🌮",
                createdAt: Date()
            )
        )
        .navigationDestination(for: Restaurant.self) { restaurant in
            RestaurantDetailView(restaurant: restaurant)
        }
    }
}

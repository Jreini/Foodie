import SwiftUI

// Index of the lists you're part of, plus a way to start a new one.
struct SharedListsView: View {
    @State private var viewModel = SharedListsViewModel()
    @State private var showCreateSheet = false

    // Grows with the user's text size so the emoji tile never crops its glyph.
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 40

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            ForEach(viewModel.lists) { list in
                NavigationLink {
                    SharedListDetailView(list: list)
                } label: {
                    listRow(list)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteList(list) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Shared Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New List", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateListSheet { name, emoji in
                await viewModel.createList(name: name, emoji: emoji)
            }
        }
        .refreshable { await viewModel.load() }
        .overlay { statusOverlay }
        .task { await viewModel.load() }
    }

    private func listRow(_ list: SharedList) -> some View {
        HStack(spacing: AppTheme.spacingMD) {
            Text(list.displayEmoji)
                .font(.title2)
                // Scaled, not fixed at 40: the font grows with Dynamic Type but
                // a hard-coded frame doesn't, so at larger text sizes the glyph
                // was being clipped away by the rounded rect.
                .frame(width: iconSize, height: iconSize)
                .background(AppTheme.tagBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(list.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.lists.isEmpty {
            ProgressView()
        } else if viewModel.hasLoadedOnce && viewModel.lists.isEmpty {
            ContentUnavailableView {
                Label("No shared lists", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Start a list, invite friends, and build it together.")
            }
        }
    }
}

// MARK: - Create

private struct CreateListSheet: View {
    let onCreate: (String, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""
    @State private var isSaving = false

    // A short palette beats a raw text field: an emoji keyboard for a
    // single-character field is fiddly on iPhone.
    private let suggestions = ["🍽️", "🌮", "🍕", "🍜", "🍣", "🍔", "🥐", "☕️", "🍸", "🎉"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Taco Tour", text: $name)
                }

                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.spacingSM) {
                            ForEach(suggestions, id: \.self) { option in
                                Button {
                                    emoji = option
                                } label: {
                                    Text(option)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            emoji == option
                                                ? AppTheme.primaryColor.opacity(0.25)
                                                : AppTheme.tagBackground
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSM))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, AppTheme.spacingXS)
                    }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                isSaving = true
                                await onCreate(name, emoji.isEmpty ? nil : emoji)
                                isSaving = false
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SharedListsView()
    }
}

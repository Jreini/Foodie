import SwiftUI

struct TastingListView: View {
    @State private var viewModel = TastingListViewModel()
    @State private var showRandomPick = false
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                tastingListContent
            }
        }
        .background(AppTheme.screenBackground)
        .navigationTitle("Tasting List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.pickRandomEntry()
                    showRandomPick = true
                } label: {
                    Label("Random", systemImage: "dice.fill")
                }
                .disabled(viewModel.entries.isEmpty)
            }
            // Plus button opens a picker to add from the Decide tab directly
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .onAppear { viewModel.loadTastingList() }
        .alert("Random Pick!", isPresented: $showRandomPick) {
            Button("OK", role: .cancel) {}
        } message: {
            if let restaurant = viewModel.randomPick {
                Text("You should try \(restaurant.name)!")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddToTastingListSheet(viewModel: viewModel)
        }
    }

    // MARK: - Subviews

    private var tastingListContent: some View {
        List {
            ForEach(viewModel.entries) { entry in
                if let restaurant = viewModel.restaurantForEntry(entry) {
                    VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                        RestaurantRowView(restaurant: restaurant)

                        if !entry.notes.isEmpty {
                            Text(entry.notes)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .italic()
                        }

                        Text("Added \(entry.dateAdded, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .onDelete { offsets in
                viewModel.removeEntry(at: offsets)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.spacingMD) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.primaryColor.opacity(0.4))

            Text("Your tasting list is empty")
                .font(.headline)

            Text("Tap + to add a restaurant,\nor save one from Discover")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Add a Restaurant", systemImage: "plus")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, AppTheme.spacingLG)
                    .padding(.vertical, AppTheme.spacingSM)
                    .background(AppTheme.primaryColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, AppTheme.spacingSM)
            Spacer()
        }
    }
}

// MARK: - Add to Tasting List Sheet

// Searchable picker that adds a restaurant to the Tasting List
private struct AddToTastingListSheet: View {
    @Bindable var viewModel: TastingListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var notes = ""
    @State private var selectedRestaurant: Restaurant?

    // Filters available restaurants by the current search query
    private var filteredRestaurants: [Restaurant] {
        let available = viewModel.availableRestaurants
        guard !searchText.isEmpty else { return available }
        let query = searchText.lowercased()
        return available.filter {
            $0.name.lowercased().contains(query) ||
            $0.cuisineType.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let restaurant = selectedRestaurant {
                    notesForm(for: restaurant)
                } else {
                    restaurantPicker
                }
            }
            .navigationTitle(selectedRestaurant == nil
                             ? "Add to Tasting List"
                             : "Add Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if let restaurant = selectedRestaurant {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            viewModel.addRestaurant(restaurant, notes: notes)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var restaurantPicker: some View {
        List {
            if filteredRestaurants.isEmpty {
                Text(viewModel.availableRestaurants.isEmpty
                     ? "Every restaurant is already on your list!"
                     : "No matches for \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppTheme.spacingXL)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredRestaurants) { restaurant in
                    Button {
                        selectedRestaurant = restaurant
                    } label: {
                        RestaurantRowView(restaurant: restaurant)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search restaurants")
    }

    private func notesForm(for restaurant: Restaurant) -> some View {
        Form {
            Section {
                RestaurantRowView(restaurant: restaurant)
            }
            Section("Notes (optional)") {
                TextField("Why do you want to try this?", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                Button("Pick a different restaurant") {
                    selectedRestaurant = nil
                    notes = ""
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TastingListView()
    }
}

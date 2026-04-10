import SwiftUI

struct BucketListView: View {
    @State private var viewModel = BucketListViewModel()
    @State private var showRandomPick = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                bucketListContent
            }
        }
        .background(AppTheme.screenBackground)
        .navigationTitle("Bucket List")
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
        }
        .onAppear { viewModel.loadBucketList() }
        .alert("Random Pick!", isPresented: $showRandomPick) {
            Button("OK", role: .cancel) {}
        } message: {
            if let restaurant = viewModel.randomPick {
                Text("You should try \(restaurant.name)!")
            }
        }
    }

    // MARK: - Subviews

    private var bucketListContent: some View {
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

            Text("Your bucket list is empty")
                .font(.headline)

            Text("Save restaurants you want to try\nfrom the Discover tab")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        BucketListView()
    }
}

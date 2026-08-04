import SwiftUI

// The in-app inbox — the same rows the push notifications were sent from.
//
// It exists because a push is not a delivery guarantee: plenty of people decline
// the permission, and iOS only asks once. Without this screen those users would
// have no way to learn about a friend request short of opening the Friends
// screen on a hunch.
//
// Rows route through `PushRouter` rather than pushing a destination directly, so
// tapping a row and tapping the notification it came from land in exactly the
// same place — including the ones that live in a different tab.
struct NotificationsView: View {
    @State private var viewModel = NotificationsViewModel()
    @Environment(PushRouter.self) private var router

    var body: some View {
        List {
            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            ForEach(viewModel.notifications) { notification in
                Button {
                    router.route(to: notification.destination)
                } label: {
                    row(notification)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .overlay { statusOverlay }
        .task {
            await viewModel.load()
            await viewModel.markVisibleRead()
        }
    }

    private func row(_ notification: AppNotification) -> some View {
        HStack(spacing: AppTheme.spacingMD) {
            // Falls back to the notification's own symbol when the actor is
            // gone — a deleted account shouldn't leave a person-shaped hole.
            ProfileImageView(
                avatarPath: notification.actor?.avatarPath,
                size: 40,
                fallbackSymbol: notification.actor == nil
                    ? notification.iconName
                    : "person.circle.fill"
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(notification.timeAgoString)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: AppTheme.spacingSM)

            if notification.isUnread {
                Circle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, AppTheme.spacingXS)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.notifications.isEmpty {
            ProgressView()
        } else if viewModel.hasLoadedOnce && viewModel.notifications.isEmpty {
            ContentUnavailableView {
                Label("Nothing new", systemImage: "bell")
            } description: {
                Text("Friend requests and list invites show up here.")
            }
        }
    }
}

// MARK: - Navigation

// A value route, for the reason recorded on `FriendsRoute`: a view-based
// `NavigationLink` in a stack that also pushes values re-activates itself
// whenever the path changes for any other reason.
struct NotificationsRoute: Hashable {}

extension View {
    func notificationsDestination() -> some View {
        navigationDestination(for: NotificationsRoute.self) { _ in
            NotificationsView()
        }
    }
}

#Preview {
    NavigationStack {
        NotificationsView()
            .environment(PushRouter.shared)
    }
}

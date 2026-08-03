import Foundation
import Supabase

// Live implementation of `DataServiceProtocol`, backed by PostgREST.
//
// Every query here is filtered again by RLS on the server. Where a method looks
// broader than it should — `fetchActivityFeed` selects the whole table, for
// instance — the policy is what narrows it to the caller and their friends.
// Don't "tighten" those by adding client-side filters and assume that's the
// security boundary; it isn't.
struct SupabaseDataService: DataServiceProtocol {

    private var client: SupabaseClient { SupabaseService.client }

    // One screenful plus headroom, so the first page rarely needs a second.
    static let feedPageSize = 30

    private func currentUserId() throws -> UUID {
        guard let id = client.auth.currentUser?.id else {
            throw DataServiceError.notSignedIn
        }
        return id
    }

    // MARK: - People

    func fetchCurrentUser() async throws -> User {
        let userId = try currentUserId()

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { throw DataServiceError.profileMissing }
        return row.user(friendIds: try await friendIds(of: userId))
    }

    func fetchAllUsers() async throws -> [User] {
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .execute()
            .value

        return rows.map { $0.user(friendIds: []) }
    }

    func fetchFriends(for userId: UUID) async throws -> [User] {
        let ids = try await friendIds(of: userId)
        guard !ids.isEmpty else { return [] }

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value

        return rows.map { $0.user(friendIds: []) }
    }

    func friendCount(for userId: UUID) async throws -> Int {
        // SECURITY DEFINER on the server, which is the only way to get this
        // number: RLS hides other people's friendship rows from the caller.
        try await client
            .rpc("friend_count", params: FriendCountParams(target: userId))
            .execute()
            .value
    }

    // MARK: - Friendships

    func searchUsers(username: String) async throws -> [User] {
        let term = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard term.count >= 2 else { return [] }

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .ilike("username", pattern: "%\(term)%")
            .limit(25)
            .execute()
            .value

        return rows.map { $0.user(friendIds: []) }
    }

    func fetchFriendships() async throws -> [Friendship] {
        // No filter needed: the friendships SELECT policy already restricts
        // this to rows the caller is part of.
        let rows: [FriendshipRow] = try await client
            .from("friendships")
            .select()
            .execute()
            .value

        return rows.compactMap(\.friendship)
    }

    func sendFriendRequest(to userId: UUID) async throws {
        let requesterId = try currentUserId()
        guard requesterId != userId else { return }

        do {
            try await client
                .from("friendships")
                .insert(FriendshipInsert(requesterId: requesterId, addresseeId: userId))
                .execute()
        } catch where Self.isUniqueViolation(error) {
            // The unique index covers both directions, so this means an edge
            // already exists — usually they requested you first.
            throw FriendRequestError.alreadyExists
        }
    }

    func acceptFriendRequest(friendshipId: UUID) async throws {
        // The UPDATE policy allows only the addressee, so this is safe to send
        // without re-checking who's who on the client.
        try await client
            .from("friendships")
            .update(FriendshipAccept(status: "accepted", respondedAt: Date()))
            .eq("id", value: friendshipId)
            .execute()
    }

    func removeFriendship(friendshipId: UUID) async throws {
        try await client
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId)
            .execute()
    }

    func groupPickCandidates(friendIds: [UUID]) async throws -> [UUID] {
        let rows: [GroupPickRow] = try await client
            .rpc("group_pick_candidates", params: GroupPickParams(friendIds: friendIds))
            .execute()
            .value

        return rows.map(\.restaurantId)
    }

    private static func isUniqueViolation(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }

    // MARK: - Shared Lists

    func fetchLists() async throws -> [SharedList] {
        // No membership filter needed: the lists SELECT policy already limits
        // this to lists the caller belongs to.
        let rows: [ListRow] = try await client
            .from("lists")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map(\.list)
    }

    func createList(name: String, emoji: String?) async throws -> SharedList {
        let ownerId = try currentUserId()

        let row: ListRow = try await client
            .from("lists")
            .insert(ListInsert(ownerId: ownerId, name: name, emoji: emoji))
            .select()
            .single()
            .execute()
            .value

        // A trigger adds the owner to list_members — without it the list's own
        // policies would hide it from its creator the instant it was made.
        return row.list
    }

    func deleteList(id: UUID) async throws {
        try await client
            .from("lists")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func fetchListEntries(listId: UUID) async throws -> [SharedListEntry] {
        let rows: [ListEntryRow] = try await client
            .from("list_entries")
            .select()
            .eq("list_id", value: listId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map(\.entry)
    }

    @discardableResult
    func addListEntry(
        listId: UUID,
        restaurantId: UUID,
        notes: String
    ) async throws -> SharedListEntry {
        let userId = try currentUserId()

        let row: ListEntryRow = try await client
            .from("list_entries")
            .insert(
                ListEntryInsert(
                    listId: listId,
                    restaurantId: restaurantId,
                    addedBy: userId,
                    notes: notes
                )
            )
            .select()
            .single()
            .execute()
            .value

        return row.entry
    }

    func removeListEntry(entryId: UUID) async throws {
        try await client
            .from("list_entries")
            .delete()
            .eq("id", value: entryId)
            .execute()
    }

    func fetchListMembers(listId: UUID) async throws -> [SharedListMember] {
        let rows: [ListMemberRow] = try await client
            .from("list_members")
            .select()
            .eq("list_id", value: listId)
            .execute()
            .value

        return rows.compactMap(\.member)
    }

    func addListMember(listId: UUID, userId: UUID) async throws {
        // The INSERT policy allows only the list owner, so an ordinary member
        // attempting this is rejected server-side.
        try await client
            .from("list_members")
            .insert(ListMemberInsert(listId: listId, userId: userId))
            .execute()
    }

    func removeListMember(listId: UUID, userId: UUID) async throws {
        try await client
            .from("list_members")
            .delete()
            .eq("list_id", value: listId)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Realtime

    func listEntriesChanged(listId: UUID) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let channel = client.channel("list-entries-\(listId.uuidString)")

                // Filtered server-side, so this socket only carries changes for
                // the list actually on screen. RLS applies on top: a
                // non-member wouldn't receive these at all.
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "list_entries",
                    filter: .eq("list_id", value: listId)
                )

                await channel.subscribe()

                // The payload is deliberately ignored. Refetching on any change
                // handles insert, update, and delete identically, and a list
                // holds a few dozen rows at most — decoding three payload
                // shapes to save one small query isn't worth the surface area.
                for await _ in changes {
                    continuation.yield()
                }

                await channel.unsubscribe()
                await client.removeChannel(channel)
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // RLS only exposes friendship rows the caller is part of, so asking about
    // someone else's friend list legitimately comes back empty.
    private func friendIds(of userId: UUID) async throws -> [UUID] {
        let rows: [FriendshipRow] = try await client
            .from("friendships")
            .select()
            .eq("status", value: "accepted")
            .or("requester_id.eq.\(userId),addressee_id.eq.\(userId)")
            .execute()
            .value

        return rows.map { $0.requesterId == userId ? $0.addresseeId : $0.requesterId }
    }

    // MARK: - Restaurants

    func fetchAllRestaurants() async throws -> [Restaurant] {
        let rows: [RestaurantRow] = try await client
            .from("restaurants")
            .select()
            .order("name")
            .execute()
            .value

        return rows.map(\.restaurant)
    }

    func fetchRestaurant(by id: UUID) async throws -> Restaurant? {
        let rows: [RestaurantRow] = try await client
            .from("restaurants")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        return rows.first?.restaurant
    }

    func fetchRestaurants(mapkitPlaceIds: [String]) async throws -> [Restaurant] {
        let unique = Array(Set(mapkitPlaceIds))
        guard !unique.isEmpty else { return [] }

        let rows: [RestaurantRow] = try await client
            .from("restaurants")
            .select()
            .in("mapkit_place_id", values: unique)
            .execute()
            .value

        return rows.map(\.restaurant)
    }

    @discardableResult
    func ensureRestaurantPersisted(_ restaurant: Restaurant) async throws -> Restaurant {
        // Already a database row — nothing to do.
        if restaurant.isPersisted { return restaurant }

        guard let placeId = restaurant.mapkitPlaceId else {
            throw DataServiceError.unpersistablePlace
        }

        let userId = try currentUserId()

        // Conflict is resolved on mapkit_place_id rather than id, which makes
        // the database the arbiter of identity: whoever inserts first wins and
        // everyone else gets that same row back. Two people opening the same
        // restaurant can't create duplicates.
        let rows: [RestaurantRow] = try await client
            .from("restaurants")
            .upsert(
                RestaurantInsert(
                    mapkitPlaceId: placeId,
                    name: restaurant.name,
                    cuisine: restaurant.cuisineType,
                    address: restaurant.address,
                    latitude: restaurant.latitude,
                    longitude: restaurant.longitude,
                    baselineTier: restaurant.baselineTier.value,
                    createdBy: userId
                ),
                onConflict: "mapkit_place_id",
                ignoreDuplicates: true
            )
            .select()
            .execute()
            .value

        if let row = rows.first { return row.restaurant }

        // ignoreDuplicates means an existing row comes back empty, so read it.
        guard let existing = try await fetchRestaurants(mapkitPlaceIds: [placeId]).first else {
            throw DataServiceError.unpersistablePlace
        }
        return existing
    }

    // MARK: - Reviews

    func fetchReviews(for restaurantId: UUID) async throws -> [Review] {
        let rows: [ReviewRow] = try await client
            .from("reviews")
            .select()
            .eq("restaurant_id", value: restaurantId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map(\.review)
    }

    func fetchReviews(by userId: UUID) async throws -> [Review] {
        let rows: [ReviewRow] = try await client
            .from("reviews")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map(\.review)
    }

    // MARK: - Lists and Likes

    func fetchTastingList(for userId: UUID) async throws -> [TastingListEntry] {
        let rows: [TastingListRow] = try await client
            .from("tasting_list")
            .select()
            .eq("user_id", value: userId)
            .order("date_added", ascending: false)
            .execute()
            .value

        return rows.map(\.entry)
    }

    func fetchLikedRestaurantIds(for userId: UUID) async throws -> [UUID] {
        let rows: [LikeRow] = try await client
            .from("likes")
            .select("restaurant_id")
            .eq("user_id", value: userId)
            .execute()
            .value

        return rows.map(\.restaurantId)
    }

    // MARK: - Feed

    func fetchActivityFeed(for userId: UUID, before: Date?) async throws -> [FriendActivity] {
        var query = client
            .from("activities")
            .select()

        // Keyset pagination rather than an offset: the feed grows at the top,
        // so an offset would shift rows between pages.
        if let before {
            query = query.lt("created_at", value: before)
        }

        let activities: [ActivityRow] = try await query
            .order("created_at", ascending: false)
            .limit(Self.feedPageSize)
            .execute()
            .value

        guard !activities.isEmpty else { return [] }

        // Hydrated with separate bulk fetches rather than PostgREST's embedded
        // resource syntax: that would hard-code auto-generated foreign key
        // constraint names into query strings, which is brittle for no real gain
        // at this size.
        async let profiles = fetchProfiles(ids: activities.map(\.userId))
        async let restaurants = fetchRestaurants(ids: activities.compactMap(\.restaurantId))
        async let reviews = fetchReviews(ids: activities.compactMap(\.reviewId))

        let usersById = Dictionary(
            uniqueKeysWithValues: try await profiles.map { ($0.id, $0.user(friendIds: [])) }
        )
        let restaurantsById = Dictionary(
            uniqueKeysWithValues: try await restaurants.map { ($0.id, $0.restaurant) }
        )
        let reviewsById = Dictionary(
            uniqueKeysWithValues: try await reviews.map { ($0.id, $0.review) }
        )

        // Rows whose user or restaurant vanished are dropped rather than shown
        // half-rendered; a cascade delete can leave the feed briefly ahead.
        return activities.compactMap { row in
            guard
                let user = usersById[row.userId],
                let restaurantId = row.restaurantId,
                let restaurant = restaurantsById[restaurantId],
                let type = row.activityType
            else { return nil }

            return FriendActivity(
                id: row.id,
                user: user,
                restaurant: restaurant,
                activityType: type,
                timestamp: row.createdAt,
                associatedReview: row.reviewId.flatMap { reviewsById[$0] }
            )
        }
    }

    private func fetchProfiles(ids: [UUID]) async throws -> [ProfileRow] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }

        return try await client
            .from("profiles")
            .select()
            .in("id", values: unique)
            .execute()
            .value
    }

    private func fetchRestaurants(ids: [UUID]) async throws -> [RestaurantRow] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }

        return try await client
            .from("restaurants")
            .select()
            .in("id", values: unique)
            .execute()
            .value
    }

    private func fetchReviews(ids: [UUID]) async throws -> [ReviewRow] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [] }

        return try await client
            .from("reviews")
            .select()
            .in("id", values: unique)
            .execute()
            .value
    }

    // MARK: - Writes

    @discardableResult
    func addToTastingList(restaurantId: UUID, notes: String) async throws -> TastingListEntry {
        let userId = try currentUserId()

        let row: TastingListRow = try await client
            .from("tasting_list")
            .insert(TastingListInsert(userId: userId, restaurantId: restaurantId, notes: notes))
            .select()
            .single()
            .execute()
            .value

        return row.entry
    }

    func removeFromTastingList(restaurantId: UUID) async throws {
        let userId = try currentUserId()

        try await client
            .from("tasting_list")
            .delete()
            .eq("user_id", value: userId)
            .eq("restaurant_id", value: restaurantId)
            .execute()
    }

    func setLiked(_ liked: Bool, restaurantId: UUID) async throws {
        let userId = try currentUserId()

        if liked {
            // Upsert rather than insert so tapping like twice isn't an error.
            try await client
                .from("likes")
                .upsert(LikeInsert(userId: userId, restaurantId: restaurantId))
                .execute()
        } else {
            try await client
                .from("likes")
                .delete()
                .eq("user_id", value: userId)
                .eq("restaurant_id", value: restaurantId)
                .execute()
        }
    }

    func deleteAccount() async throws {
        let userId = try currentUserId()

        // Photos must go first, and from the client. Postgres refuses direct
        // deletes from storage.objects ("Use the Storage API instead"), and
        // once auth.users is gone nobody holds permission to clear these folders
        // ever again — the delete policies match on the owner's own id.
        await removeAllFiles(for: userId, in: PhotoUploadService.reviewBucket)
        await removeAllFiles(for: userId, in: PhotoUploadService.avatarBucket)

        // A SECURITY DEFINER function rather than an Edge Function: it takes no
        // arguments and can only delete the caller's own row, so there's
        // nothing to tamper with and no secret key in play.
        try await client
            .rpc("delete_current_user")
            .execute()

        // The session is now backed by a user that no longer exists; clearing
        // it locally is what returns the UI to the login screen.
        try? await client.auth.signOut()
    }

    // Best effort on purpose: someone who asked to delete their account
    // shouldn't be trapped in it because a storage call failed. The account
    // deletion above is the part that must not be blocked.
    private func removeAllFiles(for userId: UUID, in bucket: String) async {
        let folder = userId.uuidString.lowercased()

        do {
            let files = try await client.storage
                .from(bucket)
                .list(path: folder)

            let paths = files.map { "\(folder)/\($0.name)" }
            guard !paths.isEmpty else { return }

            _ = try await client.storage
                .from(bucket)
                .remove(paths: paths)
        } catch {
            #if DEBUG
            print("[Foodie] couldn't remove \(bucket) files for \(folder): \(error)")
            #endif
        }
    }

    @discardableResult
    func submitReview(
        restaurantId: UUID,
        rating: Int,
        text: String,
        moodTags: [String],
        photoPaths: [String],
        tierPlacement: RestaurantTier
    ) async throws -> Review {
        let userId = try currentUserId()

        // One review per person per restaurant is a unique constraint, so an
        // upsert edits the existing one instead of failing. The activity
        // trigger fires on INSERT only, so re-reviewing doesn't spam the feed.
        let row: ReviewRow = try await client
            .from("reviews")
            .upsert(
                ReviewInsert(
                    userId: userId,
                    restaurantId: restaurantId,
                    rating: rating,
                    body: text,
                    moodTags: moodTags,
                    photoPaths: photoPaths,
                    tierPlacement: tierPlacement.value
                ),
                onConflict: "user_id,restaurant_id"
            )
            .select()
            .single()
            .execute()
            .value

        return row.review
    }
}

// MARK: - Errors

enum DataServiceError: LocalizedError {
    case notSignedIn
    case profileMissing
    case unpersistablePlace

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You're not signed in."
        case .profileMissing:
            return "Your profile couldn't be found."
        case .unpersistablePlace:
            return "This place couldn't be saved. Try searching for it again."
        }
    }
}

// Raised when an edge between the two people already exists. The unique index
// covers both directions, so this usually means they got there first.
enum FriendRequestError: LocalizedError {
    case alreadyExists

    var errorDescription: String? {
        "You're already connected with them, or a request is pending."
    }
}

// Turns whatever came back into something worth showing a person. Raw
// PostgREST messages are useful in a log and useless on screen.
enum DataLoadFailure {
    static func message(for error: Error) -> String {
        if let error = error as? DataServiceError {
            return error.localizedDescription
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "That took too long. Try again."
            default:
                break
            }
        }
        #if DEBUG
        // The real message is worth having while building the thing.
        print("[Foodie] data error: \(error)")
        #endif
        return "Something went wrong. Pull down to try again."
    }
}

// MARK: - Row Types
//
// One per table. Kept separate from the app models because the database shape
// and the UI shape drift apart on purpose — `Restaurant.imageName`, for
// example, is a UI placeholder with no column behind it.

private struct ProfileRow: Decodable {
    let id: UUID
    let username: String?
    let name: String?
    let bio: String
    let avatarPath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, name, bio
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }

    func user(friendIds: [UUID]) -> User {
        User(
            id: id,
            name: name ?? username ?? "Foodie",
            username: username ?? "",
            avatarPath: avatarPath,
            bio: bio,
            joinDate: createdAt,
            friendIds: friendIds
        )
    }
}

private struct FriendCountParams: Encodable {
    let target: UUID
}

private struct FriendshipRow: Decodable {
    let id: UUID
    let requesterId: UUID
    let addresseeId: UUID
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case createdAt = "created_at"
    }

    // Nil for a status the app doesn't know about, which is safer than
    // guessing — an unrecognised edge is simply not shown.
    var friendship: Friendship? {
        guard let status = Friendship.Status(rawValue: status) else { return nil }
        return Friendship(
            id: id,
            requesterId: requesterId,
            addresseeId: addresseeId,
            status: status,
            createdAt: createdAt
        )
    }
}

private struct FriendshipInsert: Encodable {
    let requesterId: UUID
    let addresseeId: UUID

    // status defaults to 'pending' in the schema.
    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
    }
}

private struct FriendshipAccept: Encodable {
    let status: String
    let respondedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case respondedAt = "responded_at"
    }
}

// MARK: - Shared List Rows

private struct ListRow: Decodable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let emoji: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }

    var list: SharedList {
        SharedList(id: id, ownerId: ownerId, name: name, emoji: emoji, createdAt: createdAt)
    }
}

private struct ListInsert: Encodable {
    let ownerId: UUID
    let name: String
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case name, emoji
        case ownerId = "owner_id"
    }
}

private struct ListEntryRow: Decodable {
    let id: UUID
    let listId: UUID
    let restaurantId: UUID
    let addedBy: UUID?
    let notes: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, notes
        case listId = "list_id"
        case restaurantId = "restaurant_id"
        case addedBy = "added_by"
        case createdAt = "created_at"
    }

    var entry: SharedListEntry {
        SharedListEntry(
            id: id,
            listId: listId,
            restaurantId: restaurantId,
            addedBy: addedBy,
            notes: notes,
            createdAt: createdAt
        )
    }
}

private struct ListEntryInsert: Encodable {
    let listId: UUID
    let restaurantId: UUID
    let addedBy: UUID
    let notes: String

    enum CodingKeys: String, CodingKey {
        case notes
        case listId = "list_id"
        case restaurantId = "restaurant_id"
        case addedBy = "added_by"
    }
}

private struct ListMemberRow: Decodable {
    let listId: UUID
    let userId: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case role
        case listId = "list_id"
        case userId = "user_id"
    }

    var member: SharedListMember? {
        guard let role = SharedListMember.Role(rawValue: role) else { return nil }
        return SharedListMember(listId: listId, userId: userId, role: role)
    }
}

private struct ListMemberInsert: Encodable {
    let listId: UUID
    let userId: UUID

    // role defaults to 'member' in the schema.
    enum CodingKeys: String, CodingKey {
        case listId = "list_id"
        case userId = "user_id"
    }
}

private struct GroupPickParams: Encodable {
    let friendIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case friendIds = "friend_ids"
    }
}

private struct GroupPickRow: Decodable {
    let restaurantId: UUID
    let votes: Int

    enum CodingKeys: String, CodingKey {
        case votes
        case restaurantId = "restaurant_id"
    }
}

private struct RestaurantRow: Decodable {
    let id: UUID
    let mapkitPlaceId: String?
    let name: String
    let cuisine: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let priceLevel: Int?
    let baselineTier: Double
    let averageTier: Double
    let averageRating: Double
    let tags: [String]
    let hoursDescription: String?
    let isOpenNow: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, cuisine, address, latitude, longitude, tags
        case mapkitPlaceId = "mapkit_place_id"
        case priceLevel = "price_level"
        case baselineTier = "baseline_tier"
        case averageTier = "average_tier"
        case averageRating = "average_rating"
        case hoursDescription = "hours_description"
        case isOpenNow = "is_open_now"
    }

    var restaurant: Restaurant {
        Restaurant(
            id: id,
            mapkitPlaceId: mapkitPlaceId,
            name: name,
            cuisineType: cuisine ?? "",
            address: address ?? "",
            latitude: latitude ?? 0,
            longitude: longitude ?? 0,
            averageRating: averageRating,
            priceLevel: priceLevel,
            imageName: "fork.knife.circle.fill",
            hoursDescription: hoursDescription,
            tags: tags,
            isOpenNow: isOpenNow,
            baselineTier: RestaurantTier(baselineTier),
            averageTier: RestaurantTier(averageTier),
            isPersisted: true
        )
    }
}

private struct RestaurantInsert: Encodable {
    let mapkitPlaceId: String
    let name: String
    let cuisine: String
    let address: String
    let latitude: Double
    let longitude: Double
    let baselineTier: Double
    let createdBy: UUID

    // average_tier, average_rating and review_count are deliberately absent:
    // they're trigger-maintained, and the column defaults cover a brand-new
    // row until the first review arrives.
    enum CodingKeys: String, CodingKey {
        case name, cuisine, address, latitude, longitude
        case mapkitPlaceId = "mapkit_place_id"
        case baselineTier = "baseline_tier"
        case createdBy = "created_by"
    }
}

private struct ReviewRow: Decodable {
    let id: UUID
    let userId: UUID
    let restaurantId: UUID
    let rating: Int
    let body: String
    let moodTags: [String]
    let photoPaths: [String]
    let tierPlacement: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rating, body
        case userId = "user_id"
        case restaurantId = "restaurant_id"
        case moodTags = "mood_tags"
        case photoPaths = "photo_paths"
        case tierPlacement = "tier_placement"
        case createdAt = "created_at"
    }

    // The model calls it `text`; the column is `body`, because a column named
    // `text` sitting next to the type named text reads badly in SQL.
    var review: Review {
        Review(
            id: id,
            userId: userId,
            restaurantId: restaurantId,
            rating: rating,
            text: body,
            moodTags: moodTags,
            photoNames: photoPaths,
            createdAt: createdAt,
            tierPlacement: RestaurantTier(tierPlacement)
        )
    }
}

private struct TastingListRow: Decodable {
    let id: UUID
    let userId: UUID
    let restaurantId: UUID
    let notes: String
    let dateAdded: Date

    enum CodingKeys: String, CodingKey {
        case id, notes
        case userId = "user_id"
        case restaurantId = "restaurant_id"
        case dateAdded = "date_added"
    }

    var entry: TastingListEntry {
        TastingListEntry(
            id: id,
            userId: userId,
            restaurantId: restaurantId,
            dateAdded: dateAdded,
            notes: notes
        )
    }
}

private struct LikeRow: Decodable {
    let restaurantId: UUID

    enum CodingKeys: String, CodingKey {
        case restaurantId = "restaurant_id"
    }
}

private struct ActivityRow: Decodable {
    let id: UUID
    let userId: UUID
    let restaurantId: UUID?
    let type: String
    let reviewId: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type
        case userId = "user_id"
        case restaurantId = "restaurant_id"
        case reviewId = "review_id"
        case createdAt = "created_at"
    }

    // ActivityType's raw values are display strings ("reviewed", "liked"), so
    // they can't double as the database's enum values.
    var activityType: ActivityType? {
        switch type {
        case "review":      return .review
        case "like":        return .liked
        case "tasting_add": return .addedToTastingList
        case "check_in":    return .checkIn
        default:            return nil
        }
    }
}

// MARK: - Insert Payloads

private struct TastingListInsert: Encodable {
    let userId: UUID
    let restaurantId: UUID
    let notes: String

    enum CodingKeys: String, CodingKey {
        case notes
        case userId = "user_id"
        case restaurantId = "restaurant_id"
    }
}

private struct LikeInsert: Encodable {
    let userId: UUID
    let restaurantId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case restaurantId = "restaurant_id"
    }
}

private struct ReviewInsert: Encodable {
    let userId: UUID
    let restaurantId: UUID
    let rating: Int
    let body: String
    let moodTags: [String]
    let photoPaths: [String]
    let tierPlacement: Double

    enum CodingKeys: String, CodingKey {
        case rating, body
        case userId = "user_id"
        case restaurantId = "restaurant_id"
        case moodTags = "mood_tags"
        case photoPaths = "photo_paths"
        case tierPlacement = "tier_placement"
    }
}

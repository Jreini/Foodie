import Foundation

class MockDataService: DataServiceProtocol {

    // MARK: - Stable UUIDs so relationships stay consistent

    static let currentUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let friend1Id     = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let friend2Id     = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let friend3Id     = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    static let restaurant1Id = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    static let restaurant2Id = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    static let restaurant3Id = UUID(uuidString: "00000000-0000-0000-0001-000000000003")!
    static let restaurant4Id = UUID(uuidString: "00000000-0000-0000-0001-000000000004")!
    static let restaurant5Id = UUID(uuidString: "00000000-0000-0000-0001-000000000005")!
    static let restaurant6Id = UUID(uuidString: "00000000-0000-0000-0001-000000000006")!
    static let restaurant7Id = UUID(uuidString: "00000000-0000-0000-0001-000000000007")!
    static let restaurant8Id = UUID(uuidString: "00000000-0000-0000-0001-000000000008")!

    // MARK: - Users

    lazy var users: [User] = [
        User(
            id: Self.currentUserId,
            name: "Justin Reini",
            username: "justineats",
            profileImageName: "person.circle.fill",
            bio: "Always hunting for the best tacos in town.",
            joinDate: date(2025, 1, 15),
            friendIds: [Self.friend1Id, Self.friend2Id, Self.friend3Id]
        ),
        User(
            id: Self.friend1Id,
            name: "Mia Chen",
            username: "miabites",
            profileImageName: "person.circle.fill",
            bio: "Sushi snob & coffee addict.",
            joinDate: date(2025, 2, 3),
            friendIds: [Self.currentUserId, Self.friend2Id]
        ),
        User(
            id: Self.friend2Id,
            name: "Alex Rivera",
            username: "alexfoodie",
            profileImageName: "person.circle.fill",
            bio: "Will drive 2 hours for good BBQ.",
            joinDate: date(2025, 3, 20),
            friendIds: [Self.currentUserId, Self.friend1Id, Self.friend3Id]
        ),
        User(
            id: Self.friend3Id,
            name: "Sam Patel",
            username: "samcooks",
            profileImageName: "person.circle.fill",
            bio: "Home cook by day, restaurant explorer by night.",
            joinDate: date(2025, 4, 10),
            friendIds: [Self.currentUserId, Self.friend2Id]
        ),
    ]

    // MARK: - Restaurants

    lazy var restaurants: [Restaurant] = [
        Restaurant(
            id: Self.restaurant1Id,
            name: "Sakura Sushi",
            cuisineType: "Japanese",
            address: "123 Cherry Blossom Ln",
            latitude: 34.0522, longitude: -118.2437,
            averageRating: 4.5, priceLevel: 3,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "11 AM – 10 PM",
            tags: ["date night", "fresh fish", "sake bar"],
            isOpenNow: true,
            // Upscale sushi — sits between casual and fine dining
            baselineTier: RestaurantTier(0.72),
            averageTier: RestaurantTier(0.72)
        ),
        Restaurant(
            id: Self.restaurant2Id,
            name: "Taco Libre",
            cuisineType: "Mexican",
            address: "456 Fiesta Ave",
            latitude: 34.0195, longitude: -118.4912,
            averageRating: 4.8, priceLevel: 1,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "9 AM – 11 PM",
            tags: ["casual", "street food", "spicy"],
            isOpenNow: true,
            // Quick street food — squarely fast-casual
            baselineTier: RestaurantTier(0.20),
            averageTier: RestaurantTier(0.20)
        ),
        Restaurant(
            id: Self.restaurant3Id,
            name: "Bella Napoli",
            cuisineType: "Italian",
            address: "789 Olive Garden Dr",
            latitude: 34.0407, longitude: -118.2468,
            averageRating: 4.2, priceLevel: 3,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "12 PM – 10 PM",
            tags: ["romantic", "wine list", "pasta"],
            isOpenNow: true,
            // Romantic Italian with a wine list — upscale casual
            baselineTier: RestaurantTier(0.68),
            averageTier: RestaurantTier(0.68)
        ),
        Restaurant(
            id: Self.restaurant4Id,
            name: "Smokey Joe's BBQ",
            cuisineType: "BBQ",
            address: "321 Hickory Smoke Rd",
            latitude: 34.0622, longitude: -118.3050,
            averageRating: 4.6, priceLevel: 2,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "11 AM – 9 PM",
            tags: ["casual", "smoked meats", "family friendly"],
            isOpenNow: false,
            // Classic casual dining
            baselineTier: RestaurantTier(0.50),
            averageTier: RestaurantTier(0.50)
        ),
        Restaurant(
            id: Self.restaurant5Id,
            name: "Golden Dragon",
            cuisineType: "Chinese",
            address: "555 Dynasty Blvd",
            latitude: 34.0553, longitude: -118.2498,
            averageRating: 4.0, priceLevel: 2,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "10 AM – 10 PM",
            tags: ["dim sum", "family style", "late night"],
            isOpenNow: true,
            // Family-style casual dining
            baselineTier: RestaurantTier(0.45),
            averageTier: RestaurantTier(0.45)
        ),
        Restaurant(
            id: Self.restaurant6Id,
            name: "Café Parisien",
            cuisineType: "French",
            address: "88 Rue de la Paix",
            latitude: 34.0481, longitude: -118.2590,
            averageRating: 4.7, priceLevel: 4,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "8 AM – 11 PM",
            tags: ["fine dining", "brunch", "pastries"],
            isOpenNow: true,
            // Tagged fine dining in the source data
            baselineTier: RestaurantTier(0.92),
            averageTier: RestaurantTier(0.92)
        ),
        Restaurant(
            id: Self.restaurant7Id,
            name: "Bombay Spice",
            cuisineType: "Indian",
            address: "42 Curry Lane",
            latitude: 34.0390, longitude: -118.2660,
            averageRating: 4.3, priceLevel: 2,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "11 AM – 10 PM",
            tags: ["spicy", "vegetarian options", "cozy"],
            isOpenNow: true,
            // Cozy neighborhood casual
            baselineTier: RestaurantTier(0.48),
            averageTier: RestaurantTier(0.48)
        ),
        Restaurant(
            id: Self.restaurant8Id,
            name: "Seoul Kitchen",
            cuisineType: "Korean",
            address: "77 Kimchi St",
            latitude: 34.0620, longitude: -118.3089,
            averageRating: 4.4, priceLevel: 2,
            imageName: "fork.knife.circle.fill",
            hoursDescription: "11 AM – 10 PM",
            tags: ["KBBQ", "trendy", "group friendly"],
            isOpenNow: false,
            // Trendy group spot — between casual and upscale
            baselineTier: RestaurantTier(0.55),
            averageTier: RestaurantTier(0.55)
        ),
    ]

    // MARK: - Reviews

    lazy var reviews: [Review] = [
        Review(id: UUID(), userId: Self.friend1Id, restaurantId: Self.restaurant1Id,
               rating: 5, text: "Best omakase I've ever had. The salmon was insane.",
               moodTags: ["romantic", "special occasion"], photoNames: [],
               createdAt: hoursAgo(2), tierPlacement: RestaurantTier(0.75)),
        Review(id: UUID(), userId: Self.friend2Id, restaurantId: Self.restaurant2Id,
               rating: 5, text: "The al pastor tacos are life-changing. Cash only but worth it!",
               moodTags: ["casual", "late night"], photoNames: [],
               createdAt: hoursAgo(5), tierPlacement: RestaurantTier(0.18)),
        Review(id: UUID(), userId: Self.friend3Id, restaurantId: Self.restaurant3Id,
               rating: 4, text: "Incredible cacio e pepe. Service was a tad slow.",
               moodTags: ["date night", "cozy"], photoNames: [],
               createdAt: hoursAgo(8), tierPlacement: RestaurantTier(0.66)),
        Review(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant4Id,
               rating: 5, text: "Brisket melts in your mouth. Get the mac and cheese too.",
               moodTags: ["casual", "comfort food"], photoNames: [],
               createdAt: daysAgo(1), tierPlacement: RestaurantTier(0.52)),
        Review(id: UUID(), userId: Self.friend1Id, restaurantId: Self.restaurant5Id,
               rating: 4, text: "Solid dim sum. Go early on weekends to avoid the wait.",
               moodTags: ["family", "brunch"], photoNames: [],
               createdAt: daysAgo(1), tierPlacement: RestaurantTier(0.43)),
        Review(id: UUID(), userId: Self.friend2Id, restaurantId: Self.restaurant6Id,
               rating: 5, text: "Felt like I was in Paris. The croissants are flaky perfection.",
               moodTags: ["romantic", "brunch"], photoNames: [],
               createdAt: daysAgo(2), tierPlacement: RestaurantTier(0.94)),
        Review(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant7Id,
               rating: 4, text: "Butter chicken here is legit. Naan is fresh out of the tandoor.",
               moodTags: ["cozy", "spicy"], photoNames: [],
               createdAt: daysAgo(2), tierPlacement: RestaurantTier(0.46)),
        Review(id: UUID(), userId: Self.friend3Id, restaurantId: Self.restaurant8Id,
               rating: 4, text: "Great KBBQ spot for groups. Unlimited meat for a fair price.",
               moodTags: ["group friendly", "fun"], photoNames: [],
               createdAt: daysAgo(3), tierPlacement: RestaurantTier(0.53)),
        Review(id: UUID(), userId: Self.friend1Id, restaurantId: Self.restaurant3Id,
               rating: 5, text: "Came back for the tiramisu. Did not disappoint.",
               moodTags: ["date night", "dessert"], photoNames: [],
               createdAt: daysAgo(4), tierPlacement: RestaurantTier(0.70)),
        Review(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant2Id,
               rating: 5, text: "Third visit this month. The horchata is addictive.",
               moodTags: ["casual", "quick bite"], photoNames: [],
               createdAt: daysAgo(5), tierPlacement: RestaurantTier(0.22)),
        Review(id: UUID(), userId: Self.friend2Id, restaurantId: Self.restaurant8Id,
               rating: 5, text: "Best Korean fried chicken in the city. Order extra sauce.",
               moodTags: ["trendy", "late night"], photoNames: [],
               createdAt: daysAgo(6), tierPlacement: RestaurantTier(0.57)),
        Review(id: UUID(), userId: Self.friend3Id, restaurantId: Self.restaurant1Id,
               rating: 4, text: "Sashimi was super fresh. A bit pricey but worth a splurge.",
               moodTags: ["special occasion", "fresh"], photoNames: [],
               createdAt: daysAgo(7), tierPlacement: RestaurantTier(0.70)),
    ]

    // MARK: - Tasting List

    lazy var tastingListEntries: [TastingListEntry] = [
        TastingListEntry(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant6Id,
                         dateAdded: daysAgo(3), notes: "Need to try the tasting menu"),
        TastingListEntry(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant8Id,
                         dateAdded: daysAgo(5), notes: "Sam says the KBBQ is amazing"),
        TastingListEntry(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant1Id,
                         dateAdded: daysAgo(10), notes: "Omakase night with Mia"),
        TastingListEntry(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant5Id,
                         dateAdded: daysAgo(14), notes: "Dim sum brunch this weekend?"),
        TastingListEntry(id: UUID(), userId: Self.currentUserId, restaurantId: Self.restaurant3Id,
                         dateAdded: daysAgo(20), notes: "Heard the pasta is incredible"),
    ]

    // MARK: - Liked restaurant IDs (restaurants the current user has positively rated)

    // Mirrors the mock users' friendIds so the friends screen has something to
    // show in previews: everyone is already an accepted friend.
    lazy var friendships: [Friendship] = [
        Friendship(id: UUID(), requesterId: Self.currentUserId, addresseeId: Self.friend1Id,
                   status: .accepted, createdAt: Date()),
        Friendship(id: UUID(), requesterId: Self.currentUserId, addresseeId: Self.friend2Id,
                   status: .accepted, createdAt: Date()),
        Friendship(id: UUID(), requesterId: Self.friend3Id, addresseeId: Self.currentUserId,
                   status: .pending, createdAt: Date())
    ]

    lazy var likedRestaurantIds: [UUID] = [
        Self.restaurant2Id,
        Self.restaurant4Id,
        Self.restaurant7Id,
    ]

    // MARK: - Activity Feed (pre-built from reviews + other actions)

    lazy var activityFeed: [FriendActivity] = {
        var activities: [FriendActivity] = []

        // Turn friend reviews into activity items
        for review in reviews where review.userId != Self.currentUserId {
            guard let user = users.first(where: { $0.id == review.userId }),
                  let restaurant = restaurants.first(where: { $0.id == review.restaurantId }) else { continue }
            activities.append(FriendActivity(
                id: UUID(), user: user, restaurant: restaurant,
                activityType: .review, timestamp: review.createdAt,
                associatedReview: review
            ))
        }

        // Sprinkle in some non-review activities
        if let mia = users.first(where: { $0.id == Self.friend1Id }),
           let taco = restaurants.first(where: { $0.id == Self.restaurant2Id }) {
            activities.append(FriendActivity(
                id: UUID(), user: mia, restaurant: taco,
                activityType: .checkIn, timestamp: hoursAgo(1),
                associatedReview: nil
            ))
        }

        if let alex = users.first(where: { $0.id == Self.friend2Id }),
           let bombay = restaurants.first(where: { $0.id == Self.restaurant7Id }) {
            activities.append(FriendActivity(
                id: UUID(), user: alex, restaurant: bombay,
                activityType: .addedToTastingList, timestamp: hoursAgo(3),
                associatedReview: nil
            ))
        }

        if let sam = users.first(where: { $0.id == Self.friend3Id }),
           let cafe = restaurants.first(where: { $0.id == Self.restaurant6Id }) {
            activities.append(FriendActivity(
                id: UUID(), user: sam, restaurant: cafe,
                activityType: .liked, timestamp: hoursAgo(6),
                associatedReview: nil
            ))
        }

        return activities.sorted { $0.timestamp > $1.timestamp }
    }()

    // MARK: - Protocol Methods
    //
    // Everything is `async throws` to match the live service. None of it
    // actually suspends or fails — the mock is in-memory — but sharing the
    // signature is what lets previews stand in for the real thing.

    func fetchCurrentUser() async throws -> User {
        users.first(where: { $0.id == Self.currentUserId })!
    }

    func fetchAllUsers() async throws -> [User] {
        users
    }

    func fetchFriends(for userId: UUID) async throws -> [User] {
        guard let user = users.first(where: { $0.id == userId }) else { return [] }
        return users.filter { user.friendIds.contains($0.id) }
    }

    // MARK: - Friendships

    func searchUsers(username: String) async throws -> [User] {
        let term = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard term.count >= 2 else { return [] }
        return users.filter { $0.username.lowercased().contains(term) }
    }

    func fetchFriendships() async throws -> [Friendship] {
        friendships
    }

    func sendFriendRequest(to userId: UUID) async throws {
        guard userId != Self.currentUserId else { return }
        guard !friendships.contains(where: {
            $0.otherUserId(from: Self.currentUserId) == userId
        }) else {
            throw FriendRequestError.alreadyExists
        }

        friendships.append(
            Friendship(
                id: UUID(),
                requesterId: Self.currentUserId,
                addresseeId: userId,
                status: .pending,
                createdAt: Date()
            )
        )
    }

    func acceptFriendRequest(friendshipId: UUID) async throws {
        guard let index = friendships.firstIndex(where: { $0.id == friendshipId }) else { return }
        let existing = friendships[index]
        friendships[index] = Friendship(
            id: existing.id,
            requesterId: existing.requesterId,
            addresseeId: existing.addresseeId,
            status: .accepted,
            createdAt: existing.createdAt
        )
    }

    func removeFriendship(friendshipId: UUID) async throws {
        friendships.removeAll { $0.id == friendshipId }
    }

    func groupPickCandidates(friendIds: [UUID]) async throws -> [UUID] {
        // The real version counts overlap across everyone's likes and tasting
        // lists in SQL. The mock just offers what the current user saved.
        let tasting = tastingListEntries
            .filter { $0.userId == Self.currentUserId }
            .map(\.restaurantId)
        return Array(Set(likedRestaurantIds + tasting))
    }

    func fetchAllRestaurants() async throws -> [Restaurant] {
        restaurants.map(withRecomputedAverageTier)
    }

    func fetchRestaurant(by id: UUID) async throws -> Restaurant? {
        restaurants.first(where: { $0.id == id }).map(withRecomputedAverageTier)
    }

    func fetchRestaurants(mapkitPlaceIds: [String]) async throws -> [Restaurant] {
        let wanted = Set(mapkitPlaceIds)
        return restaurants
            .filter { $0.mapkitPlaceId.map(wanted.contains) ?? false }
            .map(withRecomputedAverageTier)
    }

    @discardableResult
    func ensureRestaurantPersisted(_ restaurant: Restaurant) async throws -> Restaurant {
        if let existing = restaurants.first(where: {
            $0.id == restaurant.id || ($0.mapkitPlaceId != nil && $0.mapkitPlaceId == restaurant.mapkitPlaceId)
        }) {
            return existing
        }

        var stored = restaurant
        stored.isPersisted = true
        restaurants.append(stored)
        return stored
    }

    // Return a copy of the restaurant with averageTier recomputed from the
    // baseline plus every review's tierPlacement. Keeps the mock consistent
    // with how a real backend would aggregate crowd placements.
    private func withRecomputedAverageTier(_ restaurant: Restaurant) -> Restaurant {
        let placements = reviews
            .filter { $0.restaurantId == restaurant.id }
            .map { $0.tierPlacement }
        var copy = restaurant
        copy.averageTier = TierFlaggingService.recomputeAverageTier(
            baseline: restaurant.baselineTier,
            placements: placements
        )
        return copy
    }

    func fetchReviews(for restaurantId: UUID) async throws -> [Review] {
        reviews.filter { $0.restaurantId == restaurantId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchReviews(by userId: UUID) async throws -> [Review] {
        reviews.filter { $0.userId == userId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchTastingList(for userId: UUID) async throws -> [TastingListEntry] {
        tastingListEntries.filter { $0.userId == userId }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    func fetchActivityFeed(for userId: UUID, before: Date?) async throws -> [FriendActivity] {
        guard let before else { return activityFeed }
        return activityFeed.filter { $0.timestamp < before }
    }

    func fetchLikedRestaurantIds(for userId: UUID) async throws -> [UUID] {
        likedRestaurantIds
    }

    // MARK: - Writes
    //
    // Mutates the in-memory sample data so previews behave like the real thing
    // for the length of a session. Nothing persists across launches.

    @discardableResult
    func addToTastingList(restaurantId: UUID, notes: String) async throws -> TastingListEntry {
        if let existing = tastingListEntries.first(where: {
            $0.userId == Self.currentUserId && $0.restaurantId == restaurantId
        }) {
            return existing
        }

        let entry = TastingListEntry(
            id: UUID(),
            userId: Self.currentUserId,
            restaurantId: restaurantId,
            dateAdded: Date(),
            notes: notes
        )
        tastingListEntries.insert(entry, at: 0)
        return entry
    }

    func removeFromTastingList(restaurantId: UUID) async throws {
        tastingListEntries.removeAll {
            $0.userId == Self.currentUserId && $0.restaurantId == restaurantId
        }
    }

    func setLiked(_ liked: Bool, restaurantId: UUID) async throws {
        if liked {
            guard !likedRestaurantIds.contains(restaurantId) else { return }
            likedRestaurantIds.append(restaurantId)
        } else {
            likedRestaurantIds.removeAll { $0 == restaurantId }
        }
    }

    @discardableResult
    func submitReview(
        restaurantId: UUID,
        rating: Int,
        text: String,
        moodTags: [String],
        tierPlacement: RestaurantTier
    ) async throws -> Review {
        let review = Review(
            id: UUID(),
            userId: Self.currentUserId,
            restaurantId: restaurantId,
            rating: rating,
            text: text,
            moodTags: moodTags,
            photoNames: [],
            createdAt: Date(),
            tierPlacement: tierPlacement
        )

        // One review per person per restaurant, matching the database's
        // unique constraint.
        reviews.removeAll { $0.userId == Self.currentUserId && $0.restaurantId == restaurantId }
        reviews.insert(review, at: 0)
        return review
    }

    // MARK: - Date Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func hoursAgo(_ hours: Int) -> Date {
        Date().addingTimeInterval(-Double(hours) * 3600)
    }

    private func daysAgo(_ days: Int) -> Date {
        Date().addingTimeInterval(-Double(days) * 86400)
    }
}

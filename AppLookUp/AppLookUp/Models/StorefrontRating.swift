import Foundation

/// Ratings live per storefront, so the same app scores differently in every country —
/// and in some it isn't on sale at all.
struct StorefrontRating: Identifiable, Sendable {

    enum Status: Sendable {
        case rated(average: Double, count: Int)
        case listedButUnrated
        case notAvailable
    }

    let storefront: Storefront
    let status: Status
    var id: String { storefront.code }

    var average: Double? {
        if case let .rated(average, _) = status { return average }
        return nil
    }

    var count: Int {
        if case let .rated(_, count) = status { return count }
        return 0
    }

    var isAvailable: Bool {
        if case .notAvailable = status { return false }
        return true
    }
}

/// Aggregate view of one app across every storefront that was checked.
struct WorldRatingSummary: Sendable {

    let results: [StorefrontRating]

    /// Sorted by rating volume, biggest market first.
    var rated: [StorefrontRating] {
        results.filter { $0.average != nil }.sorted { $0.count > $1.count }
    }

    var unavailable: [StorefrontRating] { results.filter { !$0.isAvailable } }

    var totalRatings: Int { rated.reduce(0) { $0 + $1.count } }

    /// Ratings-weighted mean, which is the number Apple would show if it pooled every store.
    var weightedAverage: Double? {
        guard totalRatings > 0 else { return nil }
        let sum = rated.reduce(0.0) { $0 + ($1.average ?? 0) * Double($1.count) }
        return sum / Double(totalRatings)
    }

    var best: StorefrontRating? { rated.filter { $0.count >= 20 }.max { lhs, rhs in (lhs.average ?? 0) < (rhs.average ?? 0) } }
    var worst: StorefrontRating? { rated.filter { $0.count >= 20 }.min { lhs, rhs in (lhs.average ?? 0) < (rhs.average ?? 0) } }

    var isEmpty: Bool { results.isEmpty }
}


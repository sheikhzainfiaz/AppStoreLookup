import Foundation

// MARK: - Ratings velocity

/// One day's reading of an app's cumulative rating count in one storefront.
struct RatingSnapshot: Codable, Sendable, Identifiable {
    let date: Date
    let count: Int
    let average: Double
    var id: Date { date }
}

/// A download range inferred from ratings velocity.
///
/// The conversion rests on one uncertain number: what share of installs leave a rating. Since
/// iOS 11's native prompt that typically lands somewhere between 0.5% and 2%, varying with how
/// aggressively the app asks, its category, and its country. So this reports a range, not a
/// figure — a point estimate here would be false precision.
struct DownloadEstimate: Sendable {

    static let lowestRatingRate = 0.005
    static let highestRatingRate = 0.020

    let ratingsPerDay: Double
    let spanDays: Double
    let sampleCount: Int

    var lowDailyInstalls: Int { Int((ratingsPerDay / Self.highestRatingRate).rounded()) }
    var highDailyInstalls: Int { Int((ratingsPerDay / Self.lowestRatingRate).rounded()) }

    /// Under a week of readings, day-of-week effects dominate and the number swings wildly.
    var isReliable: Bool { spanDays >= 7 }

    init?(history: [RatingSnapshot]) {
        guard let first = history.first, let last = history.last, history.count >= 2 else { return nil }

        let span = last.date.timeIntervalSince(first.date) / 86_400
        guard span >= 0.5 else { return nil }

        let delta = Double(last.count - first.count)
        guard delta >= 0 else { return nil } // Apple occasionally resets counts on a store change.

        ratingsPerDay = delta / span
        spanDays = span
        sampleCount = history.count
    }
}


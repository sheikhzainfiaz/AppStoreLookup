import Foundation

/// Ratings velocity is the only download-shaped signal you can measure yourself rather than
/// buy. `userRatingCount` is cumulative, so the day-over-day delta is genuine new ratings.
@MainActor
final class RatingHistoryStore {

    static let shared = RatingHistoryStore()
    private let defaults = UserDefaults.standard
    private let prefix = "ratingHistory."

    private init() {}

    private func key(trackID: Int, country: String) -> String {
        "\(prefix)\(trackID).\(country)"
    }

    func history(trackID: Int, country: String) -> [RatingSnapshot] {
        guard let data = defaults.data(forKey: key(trackID: trackID, country: country)) else { return [] }
        let decoded = (try? JSONDecoder().decode([RatingSnapshot].self, from: data)) ?? []
        return decoded.sorted { $0.date < $1.date }
    }

    /// Keeps one reading per calendar day; a second lookup the same day overwrites the first.
    func record(trackID: Int, country: String, count: Int, average: Double) {
        var entries = history(trackID: trackID, country: country)
        let today = Calendar.current.startOfDay(for: .now)

        entries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }
        entries.append(RatingSnapshot(date: .now, count: count, average: average))
        entries = entries.suffix(180)

        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key(trackID: trackID, country: country))
        }
    }

    func reset(trackID: Int, country: String) {
        defaults.removeObject(forKey: key(trackID: trackID, country: country))
    }
}


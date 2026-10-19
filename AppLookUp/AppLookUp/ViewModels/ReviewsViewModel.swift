import Foundation
import Observation

/// The Reviews card in the Lookup report: paging, sorting and the local-ordering fallback.
@Observable
@MainActor
final class ReviewsViewModel {

    /// Which app and storefront the feed is pointed at.
    struct Source: Equatable {
        let trackID: Int
        let country: String
    }

    var sort: ReviewSort = .mostRecent
    private(set) var items: [AppReview] = []
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var notice: String?

    /// Once the user has asked for reviews the section stays open, even if a sort comes back
    /// empty — otherwise the sort buttons vanish and there's no way back to a tab that works.
    private(set) var hasStarted = false
    private(set) var isOrderedLocally = false

    private var source: Source?

    var digest: ReviewDigest { ReviewDigest(reviews: items) }

    var canLoadMore: Bool {
        page > 0 && page < ReviewService.maxPage && notice == nil
    }

    /// Clears everything and points the feed at a new app — or at nothing while a lookup runs.
    func reset(to source: Source?) {
        self.source = source
        items = []
        page = 0
        notice = nil
        hasStarted = false
        isOrderedLocally = false
    }

    func load(startingOver: Bool = false) async {
        guard let source, !isLoading else { return }

        hasStarted = true

        if startingOver {
            items = []
            page = 0
            notice = nil
            isOrderedLocally = false
        }

        isLoading = true
        let nextPage = page + 1
        let sort = sort

        do {
            let fetched = try await fetchPage(source: source, page: nextPage, sort: sort)

            // Bail out if the user switched tabs while this was in flight.
            guard self.sort == sort else {
                isLoading = false
                return
            }

            // The feed repeats entries near its tail, so dedupe rather than append blindly.
            let existing = Set(items.map(\.id))
            items += fetched.filter { !existing.contains($0.id) }
            if isOrderedLocally { items = sort.ordered(items) }
            page = nextPage

            if nextPage == ReviewService.maxPage {
                notice = "Apple's feed stops at 500 reviews per storefront."
            }
        } catch {
            guard self.sort == sort else {
                isLoading = false
                return
            }
            notice = items.isEmpty
                ? error.localizedDescription
                : "That's everything this storefront's feed will return."
        }
        isLoading = false
    }

    /// Re-tapping the active tab retries it, which matters when the first attempt failed.
    func changeSort(to sort: ReviewSort) async {
        self.sort = sort
        await load(startingOver: true)
    }

    /// Falls back to the recent feed, ordered locally, when a storefront won't serve this sort.
    private func fetchPage(source: Source, page: Int, sort: ReviewSort) async throws -> [AppReview] {
        if !isOrderedLocally {
            do {
                return try await ReviewService.reviews(
                    trackID: source.trackID, country: source.country, page: page, sort: sort
                )
            } catch where sort != .mostRecent {
                isOrderedLocally = true
            }
        }

        let recent = try await ReviewService.reviews(
            trackID: source.trackID, country: source.country, page: page, sort: .mostRecent
        )
        return sort.ordered(recent)
    }
}

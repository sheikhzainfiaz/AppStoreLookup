import Observation

enum RootTab: Hashable {
    case lookup, availability, earnings
}

/// The root of the app: one view model per tab, plus the hand-offs between them.
@Observable
@MainActor
final class AppViewModel {

    var selection: RootTab = .lookup

    let lookup: LookupViewModel
    let availability: AvailabilityViewModel
    let earnings: EarningsViewModel

    init() {
        lookup = LookupViewModel()
        availability = AvailabilityViewModel()
        earnings = EarningsViewModel()
    }

    /// From a failed lookup: carry the query over and sweep every storefront.
    func findWhereLive() {
        availability.query = lookup.query
        selection = .availability
        availability.start()
    }

    /// From the other tabs: open the full report for one app in one storefront.
    func openReport(query: String, country: String) {
        lookup.query = query
        lookup.country = country
        selection = .lookup
        Task { await lookup.submit() }
    }
}

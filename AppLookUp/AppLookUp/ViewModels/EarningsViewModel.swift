import Foundation
import Observation

/// The Earnings tab: actual monthly earnings from App Store Connect, shaped for display.
@Observable
@MainActor
final class EarningsViewModel {

    struct MonthBar: Identifiable {
        let key: String
        let label: String
        let usd: Double
        var id: String { key }
    }

    struct MonthSummary {
        let month: EarningsMonth
        let proceedsUSD: Double?
        let grossUSD: Double?
        let downloads: Double
        /// Month-over-month change in proceeds, as a fraction.
        let change: Double?
    }

    struct AppRow: Identifiable {
        let app: AppEarnings
        let usd: Double?
        /// Proceeds relative to the month's top earner, 0–1.
        let share: Double
        let listing: AppStoreApp?
        var id: String { app.id }
    }

    /// The month the user picked. Falls back to the store's suggestion when unset or stale.
    private var pickedMonthKey: String?

    /// The App Store Connect key sheet, while it's open.
    var setup: ASCSetupViewModel?

    private let store: EarningsStore

    convenience init() {
        self.init(store: .shared)
    }

    init(store: EarningsStore) {
        self.store = store
    }

    // MARK: Store state

    var isConfigured: Bool { store.isConfigured }
    var isLoading: Bool { store.isLoading }
    var errorMessage: String? { store.errorMessage }
    var months: [EarningsMonth] { store.months }
    var lastLoaded: Date? { store.lastLoaded }

    // MARK: Intents

    func load() async {
        await store.load()
    }

    func loadIfNeeded() async {
        if store.isConfigured, store.months.isEmpty {
            await store.load()
        }
    }

    func select(_ month: EarningsMonth) {
        pickedMonthKey = month.key
    }

    func presentSetup() {
        setup = ASCSetupViewModel(store: store) { [weak self] in
            self?.pickedMonthKey = nil
        }
    }

    func detail(for key: String) -> AppEarningsDetailViewModel {
        AppEarningsDetailViewModel(key: key, monthKey: selectedMonth?.key, store: store)
    }

    // MARK: Selection

    var selectedMonth: EarningsMonth? {
        store.month(pickedMonthKey) ?? store.month(store.suggestedMonthKey)
    }

    func isSelected(_ month: EarningsMonth) -> Bool {
        month.key == selectedMonth?.key
    }

    var selectedSummary: MonthSummary? {
        guard let month = selectedMonth else { return nil }
        let proceeds = store.totalProceedsUSD(month)

        var change: Double?
        if let proceeds,
           let previous = store.month(before: month),
           let before = store.totalProceedsUSD(previous),
           before > 0 {
            change = (proceeds - before) / before
        }

        return MonthSummary(
            month: month,
            proceedsUSD: proceeds,
            grossUSD: store.totalGrossUSD(month),
            downloads: store.totalDownloads(month),
            change: change
        )
    }

    /// Oldest first, for the chart.
    var bars: [MonthBar] {
        store.months.reversed().compactMap { month in
            store.totalProceedsUSD(month).map { MonthBar(key: month.key, label: month.shortLabel, usd: $0) }
        }
    }

    /// The selected month's apps, biggest earner first.
    var appRows: [AppRow] {
        let ranked = (selectedMonth?.apps ?? [])
            .map { (app: $0, usd: store.usd($0.proceeds)) }
            .sorted { ($0.usd ?? 0, $0.app.downloads) > ($1.usd ?? 0, $1.app.downloads) }
        let top = max(ranked.first?.usd ?? 1, 1)

        return ranked.map { entry in
            AppRow(
                app: entry.app,
                usd: entry.usd,
                share: (entry.usd ?? 0) / top,
                listing: entry.app.appleID.flatMap { store.listings[$0] }
            )
        }
    }
}

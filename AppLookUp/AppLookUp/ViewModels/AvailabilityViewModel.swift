//
//  AvailabilityViewModel.swift
//  Applookup
//
//  v2: is this app live, and in which of the 175 storefronts?
//

import Foundation
import Observation

enum AvailabilityFilter: String, CaseIterable, Identifiable {
    case live, notLive, unconfirmed
    var id: String { rawValue }

    var label: String {
        switch self {
        case .live: "Live"
        case .notLive: "Not live"
        case .unconfirmed: "Unconfirmed"
        }
    }
}

/// The Availability tab: sweeps every storefront for one app and filters the answers.
@Observable
@MainActor
final class AvailabilityViewModel {

    var query = ""
    var filter: AvailabilityFilter = .live
    var countrySearch = ""

    private(set) var report: AvailabilityReport?
    private(set) var partial: [StorefrontAvailability] = []
    private(set) var isChecking = false
    private(set) var checked = 0
    private(set) var total = Storefront.everywhere.count
    private(set) var errorMessage: String?

    private var task: Task<Void, Never>?
    /// Results from a cancelled sweep can still trickle in; the token drops them.
    private var runToken = UUID()

    var canCheck: Bool {
        !isChecking && AppStoreLookupService.identifier(from: query) != nil
    }

    var liveSoFar: Int { partial.filter(\.isLive).count }

    /// The first live listing to arrive, shown while the sweep is still running.
    var firstLiveSoFar: StorefrontAvailability? {
        partial.first { $0.storefront.code == "us" && $0.isLive } ?? partial.first(where: \.isLive)
    }

    // MARK: Filtering

    func count(for filter: AvailabilityFilter) -> Int {
        items(for: filter).count
    }

    /// The current filter tab, narrowed by the country search box.
    var visibleItems: [StorefrontAvailability] {
        let base = items(for: filter)
        let search = countrySearch.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return base }
        return base.filter {
            $0.storefront.name.localizedCaseInsensitiveContains(search)
                || $0.storefront.code.caseInsensitiveCompare(search) == .orderedSame
        }
    }

    var visibleGroups: [AvailabilityReport.RegionGroup] {
        report?.grouped(visibleItems) ?? []
    }

    private func items(for filter: AvailabilityFilter) -> [StorefrontAvailability] {
        guard let report else { return [] }
        return switch filter {
        case .live: report.live
        case .notLive: report.notLive
        case .unconfirmed: report.unconfirmed
        }
    }

    // MARK: Sweeping

    func start() {
        guard AppStoreLookupService.identifier(from: query) != nil else {
            errorMessage = LookupError.emptyInput.errorDescription
            return
        }
        run(input: query, storefronts: Storefront.everywhere, keeping: [])
    }

    /// Re-asks only the storefronts that never gave a clean answer.
    func retryUnconfirmed() {
        guard let report, !report.unconfirmed.isEmpty else { return }
        let settled = report.results.filter { !$0.isUnconfirmed }
        run(input: report.query, storefronts: report.unconfirmed.map(\.storefront), keeping: settled)
    }

    func cancel() {
        task?.cancel()
        task = nil
        runToken = UUID()
        isChecking = false
        if !partial.isEmpty {
            report = AvailabilityReport(query: query, results: partial, checkedAt: .now, isPartial: true)
        }
    }

    func clear() {
        cancel()
        query = ""
        report = nil
        partial = []
        errorMessage = nil
        countrySearch = ""
    }

    private func run(input: String, storefronts: [Storefront], keeping settled: [StorefrontAvailability]) {
        task?.cancel()

        let token = UUID()
        runToken = token
        errorMessage = nil
        report = nil
        partial = settled
        checked = settled.count
        total = settled.count + storefronts.count
        isChecking = true

        let offset = settled.count

        task = Task {
            let results = await AvailabilityService.sweep(input: input, storefronts: storefronts) { result, done, _ in
                guard self.runToken == token else { return }
                self.partial.append(result)
                self.checked = offset + done
            }

            guard self.runToken == token, !Task.isCancelled else { return }

            let merged = settled + results
            self.report = AvailabilityReport(query: input, results: merged, checkedAt: .now, isPartial: false)
            self.isChecking = false
            self.filter = merged.contains(where: \.isLive) ? .live : .notLive
        }
    }
}

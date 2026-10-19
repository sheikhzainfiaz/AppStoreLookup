//
//  Availability.swift
//  Applookup
//
//  v2: is this app live, and in which of the 175 storefronts?
//

import Foundation

// MARK: - Model

/// One storefront's answer. `unconfirmed` is kept separate from `notLive` on purpose: Apple's
/// lookup endpoint throttles hard, and a throttled request must never be reported as
/// "not available here".
struct StorefrontAvailability: Identifiable, Sendable {

    enum Status: Sendable {
        case live(AppStoreApp)
        case notLive
        case unconfirmed
    }

    let storefront: Storefront
    let status: Status

    var id: String { storefront.code }

    var app: AppStoreApp? {
        if case let .live(app) = status { return app }
        return nil
    }

    var isLive: Bool { app != nil }

    var isUnconfirmed: Bool {
        if case .unconfirmed = status { return true }
        return false
    }
}

struct AvailabilityReport: Sendable {

    let query: String
    let results: [StorefrontAvailability]
    let checkedAt: Date
    /// True when the sweep was stopped before every storefront answered.
    let isPartial: Bool

    private static func byName(_ lhs: StorefrontAvailability, _ rhs: StorefrontAvailability) -> Bool {
        lhs.storefront.name.localizedStandardCompare(rhs.storefront.name) == .orderedAscending
    }

    var live: [StorefrontAvailability] { results.filter(\.isLive).sorted(by: Self.byName) }
    var notLive: [StorefrontAvailability] {
        results.filter { !$0.isLive && !$0.isUnconfirmed }.sorted(by: Self.byName)
    }
    var unconfirmed: [StorefrontAvailability] { results.filter(\.isUnconfirmed).sorted(by: Self.byName) }

    var isLiveAnywhere: Bool { results.contains(where: \.isLive) }

    /// The listing to feature: the US one if it's live there, otherwise the storefront where
    /// the most people have rated it — the listing most people actually see.
    var featured: StorefrontAvailability? {
        let live = results.filter(\.isLive)
        return live.first { $0.storefront.code == "us" }
            ?? live.max { ($0.app?.userRatingCount ?? 0) < ($1.app?.userRatingCount ?? 0) }
    }

    struct RegionGroup: Identifiable, Sendable {
        let region: StoreRegion
        let items: [StorefrontAvailability]
        var id: StoreRegion { region }
    }

    /// Storefronts grouped the way Apple groups them.
    func grouped(_ items: [StorefrontAvailability]) -> [RegionGroup] {
        StoreRegion.allCases.compactMap { region -> RegionGroup? in
            let matching = items.filter { $0.storefront.region == region }
            return matching.isEmpty ? nil : RegionGroup(region: region, items: matching)
        }
    }

    /// Plain-text list for sharing — "Live in 142 storefronts: …".
    var shareText: String {
        let name = featured?.app?.trackName ?? query
        let countries = live.map { "\($0.storefront.flag) \($0.storefront.name)" }.joined(separator: "\n")
        return "\(name) is live in \(live.count) of \(results.count) App Store storefronts:\n\n\(countries)"
    }
}

// MARK: - Pacing

/// Shared back-off for a sweep. When any request looks throttled, every worker pauses —
/// hammering on through a 403 only extends the penalty.
actor RequestPacer {

    private var resumeAt = Date.distantPast
    private var penalty: TimeInterval = 0

    func waitTurn() async {
        let delay = resumeAt.timeIntervalSinceNow
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    func throttled() {
        penalty = min(max(penalty * 2, 2), 30)
        resumeAt = max(resumeAt, Date.now.addingTimeInterval(penalty))
    }

    func succeeded() {
        penalty = max(0, penalty * 0.7 - 0.1)
    }
}

// MARK: - Service

enum AvailabilityService {

    /// Checks `input` (track ID, bundle ID or store link) in each storefront.
    /// `onResult` fires on the main actor as each storefront answers, for live progress.
    static func sweep(
        input: String,
        storefronts: [Storefront] = Storefront.everywhere,
        maxConcurrent: Int = 5,
        onResult: @escaping (StorefrontAvailability, _ done: Int, _ total: Int) -> Void
    ) async -> [StorefrontAvailability] {

        let pacer = RequestPacer()
        let total = storefronts.count
        var completed = 0
        var collected: [StorefrontAvailability] = []

        await withTaskGroup(of: StorefrontAvailability.self) { group in
            var next = 0

            func schedule(_ storefront: Storefront) {
                group.addTask {
                    await probe(input: input, storefront: storefront, pacer: pacer)
                }
            }

            while next < min(maxConcurrent, total) {
                schedule(storefronts[next])
                next += 1
            }

            for await result in group {
                collected.append(result)
                completed += 1
                onResult(result, completed, total)

                if next < total, !Task.isCancelled {
                    schedule(storefronts[next])
                    next += 1
                }
            }
        }
        return collected
    }

    private static func probe(
        input: String,
        storefront: Storefront,
        pacer: RequestPacer,
        attempts: Int = 4
    ) async -> StorefrontAvailability {

        for _ in 0..<attempts {
            if Task.isCancelled { break }
            await pacer.waitTurn()

            do {
                let app = try await AppStoreLookupService.lookup(input, country: storefront.code)
                await pacer.succeeded()
                return .init(storefront: storefront, status: .live(app))
            } catch LookupError.notFound {
                // A clean, empty answer: Apple is telling us it isn't sold here.
                await pacer.succeeded()
                return .init(storefront: storefront, status: .notLive)
            } catch LookupError.emptyInput {
                break
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { break }
                // 403s, 5xx, dropped connections: back everyone off and retry.
                await pacer.throttled()
            }
        }
        return .init(storefront: storefront, status: .unconfirmed)
    }
}

// MARK: - State

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

@Observable
@MainActor
final class AvailabilityModel {

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

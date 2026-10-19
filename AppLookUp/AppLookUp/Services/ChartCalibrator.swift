//
//  ChartCalibrator.swift
//  Applookup
//
//  Created by Sheikh Zain Fiaz on 19/09/2026.
//


import Foundation


enum ChartCalibrator {

    enum Outcome: Sendable {
        case baselineTaken(sampled: Int)
        case fitted(RankCurve)
        case tooSoon(hoursRemaining: Double)
        case notEnoughMovement(usable: Int)
        case chartUnavailable
    }

    static func sampleRanks(depth: Int, count: Int = 28) -> [Int] {
        guard depth > 1, count > 1 else { return [1] }
        let step = log(Double(depth)) / Double(count - 1)
        let ranks = (0..<count).map { Int(exp(Double($0) * step).rounded()) }
        return Array(Set(ranks)).sorted()
    }

    static func run(
        country: String,
        genreID: Int?,
        chart: ChartKind = .free,
        depth: Int = 200,
        store: DownloadCalibrationStore,
        onProgress: @Sendable @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> Outcome {

        let entries = await ChartRankService.chartEntries(
            chart: chart, country: country, genreID: genreID, depth: depth
        )
        guard !entries.isEmpty else { return .chartUnavailable }

        let wanted = Set(sampleRanks(depth: min(depth, entries.count)))
        let targets = entries.filter { wanted.contains($0.rank) }

        // A previous pass, if there is one, decides whether this run baselines or fits.
        let previous = store.pendingSample(country: country, genreID: genreID)

        if let previous {
            let elapsed = Date.now.timeIntervalSince(previous.takenAt) / 3600
            if elapsed < 18 {
                return .tooSoon(hoursRemaining: 18 - elapsed)
            }
        }

        let readings = await ratingCounts(for: targets, country: country, onProgress: onProgress)
        let sample = ChartSample(country: country, genreID: genreID, entries: readings, takenAt: .now)

        guard let previous else {
            store.storeSample(sample)
            return .baselineTaken(sampled: readings.count)
        }

        // Join the two passes on app ID, not rank — apps move between runs, and the rank we
        // want is the one it held while it was earning those ratings. Averaging the two is the
        // closest thing to that available.
        var points: [(rank: Int, value: Double)] = []
        let before = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.trackID, $0) })

        for now in readings {
            guard let then = before[now.trackID] else { continue }
            let days = now.date.timeIntervalSince(then.date) / 86_400
            guard days >= 0.5 else { continue }

            let delta = Double(now.ratingCount - then.ratingCount)
            guard delta > 0 else { continue }

            points.append((rank: (now.rank + then.rank) / 2, value: delta / days))
        }

        store.storeSample(sample)

        guard
            points.count >= 6,
            let curve = RankCurve.fit(points: points, country: country, genreID: genreID)
        else {
            return .notEnoughMovement(usable: points.count)
        }

        store.storeCurve(curve)
        return .fitted(curve)
    }

    private static func ratingCounts(
        for targets: [(rank: Int, trackID: Int)],
        country: String,
        onProgress: @Sendable @escaping (Int, Int) -> Void
    ) async -> [ChartSampleEntry] {

        let total = targets.count
        var completed = 0
        var collected: [ChartSampleEntry] = []

        await withTaskGroup(of: ChartSampleEntry?.self) { group in
            var next = 0

            func schedule(_ target: (rank: Int, trackID: Int)) {
                group.addTask {
                    guard
                        let app = try? await AppStoreLookupService.lookup(
                            String(target.trackID), country: country
                        ),
                        let count = app.userRatingCount
                    else { return nil }
                    return ChartSampleEntry(
                        trackID: target.trackID, rank: target.rank, ratingCount: count, date: .now
                    )
                }
            }

            while next < min(4, total) {
                schedule(targets[next])
                next += 1
            }

            for await result in group {
                if let result { collected.append(result) }
                completed += 1
                onProgress(completed, total)

                if next < total {
                    schedule(targets[next])
                    next += 1
                }
            }
        }
        return collected.sorted { $0.rank < $1.rank }
    }
}

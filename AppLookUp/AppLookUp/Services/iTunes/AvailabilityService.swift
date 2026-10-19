import Foundation

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


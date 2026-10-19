import Foundation

// MARK: - Exchange rates

enum ExchangeRates {

    private static var cached: (rates: [String: Double], fetchedAt: Date)?

    /// Units of each currency per 1 USD. Keyless public feed, refreshed every six hours.
    static func perUSD() async -> [String: Double]? {
        if let cached = Self.cached, Date.now.timeIntervalSince(cached.fetchedAt) < 6 * 3600 {
            return cached.rates
        }
        guard
            let url = URL(string: "https://open.er-api.com/v6/latest/USD"),
            let (data, _) = try? await URLSession.shared.data(from: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = root["rates"] as? [String: Any]
        else { return Self.cached?.rates }

        var rates: [String: Double] = [:]
        for (code, value) in raw {
            if let number = value as? NSNumber { rates[code.uppercased()] = number.doubleValue }
        }
        guard !rates.isEmpty else { return Self.cached?.rates }
        Self.cached = (rates, .now)
        return rates
    }
}


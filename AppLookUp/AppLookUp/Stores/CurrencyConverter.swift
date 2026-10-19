import Foundation
import Observation

/// Today's exchange rates, for pricing paid apps in USD.
@Observable
@MainActor
final class CurrencyConverter {

    static let shared = CurrencyConverter()

    /// Units of each currency per 1 USD; nil until the first successful fetch.
    private(set) var rates: [String: Double]?

    private init() {}

    func refresh() async {
        if let fresh = await ExchangeRates.perUSD() { rates = fresh }
    }

    func refreshIfNeeded() async {
        if rates == nil { await refresh() }
    }

    func toUSD(_ amount: Double, currency: String) -> Double? {
        let code = currency.uppercased()
        if code == "USD" || amount == 0 { return amount }
        guard let rate = rates?[code], rate > 0 else { return nil }
        return amount / rate
    }
}

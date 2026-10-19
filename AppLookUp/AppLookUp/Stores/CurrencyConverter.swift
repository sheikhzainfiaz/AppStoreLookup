import Foundation
import Observation

/// Today's exchange rates, shared by every screen that has to total money in USD.
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

    /// Sums a per-currency dictionary. Nil if any non-zero amount can't be converted — a
    /// total that silently drops a currency would be wrong in a way nobody would notice.
    func toUSD(_ amounts: [String: Double]) -> Double? {
        var total = 0.0
        for (currency, amount) in amounts where amount != 0 {
            guard let converted = toUSD(amount, currency: currency) else { return nil }
            total += converted
        }
        return total
    }
}

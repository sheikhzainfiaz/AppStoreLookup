import Foundation

// MARK: - Formatting

func formatUSD(_ value: Double, cents: Bool = false) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
}


import Foundation

/// Lenient parsing for figures typed into text fields, where people paste "12,400" or "$3.50".
enum NumericInput {

    /// Digits only — separators, currency signs and decimal points are dropped.
    static func wholeNumber(from text: String) -> Double? {
        Double(text.filter(\.isNumber))
    }

    /// Digits and a decimal point.
    static func decimal(from text: String) -> Double? {
        Double(text.filter { $0.isNumber || $0 == "." })
    }
}

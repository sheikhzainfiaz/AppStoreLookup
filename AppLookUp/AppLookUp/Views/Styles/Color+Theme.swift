import SwiftUI

// MARK: - Colors

extension Color {
    #if os(iOS)
    static let surface = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    #else
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #endif
}


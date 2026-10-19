import SwiftUI

struct RootView: View {

    @State private var model = AppViewModel()

    var body: some View {
        TabView(selection: $model.selection) {
            Tab("Lookup", systemImage: "magnifyingglass", value: RootTab.lookup) {
                LookupScreen(model: model.lookup, onFindWhereLive: model.findWhereLive)
            }
            Tab("Availability", systemImage: "globe", value: RootTab.availability) {
                AvailabilityScreen(model: model.availability, onOpenReport: model.openReport)
            }
            Tab("Earnings", systemImage: "chart.bar.xaxis", value: RootTab.earnings) {
                EarningsScreen(model: model.earnings, onOpenReport: model.openReport)
            }
        }
    }
}

#Preview {
    RootView()
}

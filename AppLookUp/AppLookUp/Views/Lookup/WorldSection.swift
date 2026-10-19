import MapKit
import SwiftUI

// MARK: - World

struct WorldSection: View {

    let model: LookupViewModel
    @State private var showingList = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle("Ratings around the world")
                Spacer()
                if model.world != nil {
                    Picker("View", selection: $showingList) {
                        Image(systemName: "map").tag(false)
                        Image(systemName: "list.bullet").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 96)
                }
            }

            if let world = model.world {
                WorldTotals(world: world)

                if showingList {
                    WorldList(world: world, model: model)
                } else {
                    WorldMap(world: world, model: model)
                    MapLegend()
                }

                Text("Tap a country to load that storefront's listing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.isScanningWorld {
                VStack(spacing: 10) {
                    ProgressView(value: Double(model.scanned), total: Double(model.scanTotal))
                    Text("Checked \(model.scanned) of \(model.scanTotal) storefronts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple stores ratings separately in every country. Sweep all \(Storefront.all.count) storefronts to see where this app is sold and how it scores in each.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await model.scanWorld() }
                    } label: {
                        Label("Scan storefronts", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

private struct WorldTotals: View {

    let world: WorldRatingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                Totals(
                    value: world.weightedAverage.map { String(format: "%.2f", $0) } ?? "—",
                    label: "Pooled average"
                )
                Divider().frame(height: 38)
                Totals(value: world.totalRatings.formatted(), label: "Ratings counted")
                Divider().frame(height: 38)
                Totals(value: "\(world.rated.count)", label: "Stores rated")
                Divider().frame(height: 38)
                Totals(value: "\(world.unavailable.count)", label: "Not on sale")
            }

            if let best = world.best, let worst = world.worst, best.id != worst.id {
                HStack(spacing: 6) {
                    Text("Strongest \(best.storefront.flag) \(best.storefront.name)")
                    Text("·").foregroundStyle(.tertiary)
                    Text("Weakest \(worst.storefront.flag) \(worst.storefront.name)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private struct Totals: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 3) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WorldMap: View {

    let world: WorldRatingSummary
    let model: LookupViewModel

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25, longitude: 15),
            span: MKCoordinateSpan(latitudeDelta: 130, longitudeDelta: 170)
        )
    )

    private var heaviest: Int { max(world.rated.first?.count ?? 1, 1) }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(world.results) { rating in
                Annotation(rating.storefront.name, coordinate: rating.storefront.coordinate) {
                    Pin(rating: rating, scale: scale(for: rating)) {
                        Task { await model.inspect(rating.storefront) }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Bubble area tracks rating volume, on a log scale so small stores stay visible.
    private func scale(for rating: StorefrontRating) -> Double {
        guard rating.count > 0 else { return 0.55 }
        let normalized = log10(Double(rating.count) + 1) / log10(Double(heaviest) + 1)
        return 0.6 + normalized * 0.75
    }

    private struct Pin: View {
        let rating: StorefrontRating
        let scale: Double
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Group {
                    if let average = rating.average {
                        Text(String(format: "%.1f", average))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(rating.tint.gradient, in: .circle)
                    } else if rating.isAvailable {
                        Circle()
                            .fill(.gray)
                            .frame(width: 11, height: 11)
                    } else {
                        Circle()
                            .strokeBorder(.secondary.opacity(0.7), lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                    }
                }
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2)
                }
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .scaleEffect(scale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }

        private var label: String {
            switch rating.status {
            case let .rated(average, count):
                "\(rating.storefront.name): \(String(format: "%.1f", average)) stars from \(count) ratings"
            case .listedButUnrated:
                "\(rating.storefront.name): listed, no ratings yet"
            case .notAvailable:
                "\(rating.storefront.name): not on sale"
            }
        }
    }
}

private struct MapLegend: View {
    private let stops: [(Color, String)] = [
        (.green, "4.5+"), (.mint, "4.0"), (.orange, "3.0"), (.red, "under 3"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(stops, id: \.1) { color, label in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label)
                }
            }
            HStack(spacing: 4) {
                Circle().strokeBorder(.secondary, lineWidth: 1.2).frame(width: 8, height: 8)
                Text("not sold")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct WorldList: View {

    let world: WorldRatingSummary
    let model: LookupViewModel

    private var maxCount: Int { max(world.rated.first?.count ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(world.rated.enumerated()), id: \.element.id) { index, rating in
                if index > 0 { Divider() }
                Button {
                    Task { await model.inspect(rating.storefront) }
                } label: {
                    HStack(spacing: 10) {
                        Text(rating.storefront.flag)
                        Text(rating.storefront.name)
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Capsule()
                            .fill(rating.tint.opacity(0.35))
                            .frame(width: 56 * fraction(rating.count), height: 6)
                            .frame(width: 56, alignment: .leading)

                        Text(rating.count.formatted())
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)

                        Text(String(format: "%.1f", rating.average ?? 0))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 26, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            if !world.unavailable.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Not on sale in \(world.unavailable.map(\.storefront.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fraction(_ count: Int) -> Double {
        max(0.08, Double(count) / Double(maxCount))
    }
}

// MARK: - Map helpers

extension Storefront {
    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

extension StorefrontRating {
    /// Green where people like it, red where they don't, grey where it isn't sold.
    var tint: Color {
        guard let average else {
            return isAvailable ? .gray : .secondary
        }
        if average >= 4.5 { return .green }
        if average >= 4.0 { return .mint }
        if average >= 3.0 { return .orange }
        return .red
    }
}


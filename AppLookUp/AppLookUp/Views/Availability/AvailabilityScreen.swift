//
//  AvailabilityScreen.swift
//  Applookup
//
//  v2: the Availability tab.
//

import SwiftUI

struct AvailabilityScreen: View {

    @Bindable var model: AvailabilityViewModel
    /// (query, storefront code) → open the full report in the Lookup tab.
    let onOpenReport: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AvailabilitySearchBar(model: model)

                    if let message = model.errorMessage {
                        MessageBox(text: message, symbol: "exclamationmark.triangle")
                    }

                    if model.isChecking {
                        SweepProgress(model: model, onOpenReport: onOpenReport)
                    } else if let report = model.report {
                        AvailabilityResult(report: report, model: model, onOpenReport: onOpenReport)
                    } else {
                        AvailabilityHint()
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("Availability")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: model.isChecking)
        }
    }
}

// MARK: - Search

private struct AvailabilitySearchBar: View {

    @Bindable var model: AvailabilityViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)

                TextField("App ID, bundle ID, or App Store link", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(start)

                if !model.query.isEmpty {
                    Button {
                        model.clear()
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.card, in: .rect(cornerRadius: 12))

            HStack {
                Text("Checks all \(Storefront.everywhere.count) App Store storefronts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if model.isChecking {
                    Button("Stop", role: .cancel) { model.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Check", action: start)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canCheck)
                }
            }
        }
    }

    private func start() {
        focused = false
        model.start()
    }
}

private struct AvailabilityHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Is it live — and where?")
                .font(.headline)
            Text("Paste an app's ID and every storefront is asked in turn. You get a clear live / not live answer, the live listing itself, and the full list of countries it's sold in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Apple rate-limits these lookups, so a full sweep takes a minute or two. Storefronts that never answer cleanly are marked unconfirmed rather than counted as not live.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Progress

private struct SweepProgress: View {

    let model: AvailabilityViewModel
    let onOpenReport: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: Double(model.checked), total: Double(max(model.total, 1)))
                HStack {
                    Text("Checked \(model.checked) of \(model.total)")
                    Spacer()
                    Text("Live in \(model.liveSoFar) so far")
                        .foregroundStyle(model.liveSoFar > 0 ? .green : .secondary)
                }
                .font(.caption)
                .monospacedDigit()
            }
            .padding(20)
            .background(Color.card, in: .rect(cornerRadius: 14))

            // The app is usually confirmed live within the first few answers; show it right away.
            if let first = model.firstLiveSoFar, let app = first.app {
                LiveAppCard(app: app, storefront: first.storefront, onOpenReport: onOpenReport)
            }
        }
    }
}

// MARK: - Result

private struct AvailabilityResult: View {

    let report: AvailabilityReport
    @Bindable var model: AvailabilityViewModel
    let onOpenReport: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StatusBanner(report: report)

            if let featured = report.featured, let app = featured.app {
                LiveAppCard(app: app, storefront: featured.storefront, onOpenReport: onOpenReport)
            }

            if !report.unconfirmed.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        "\(report.unconfirmed.count) storefront\(report.unconfirmed.count == 1 ? "" : "s") didn't answer cleanly.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    Spacer()
                    Button("Retry those") { model.retryUnconfirmed() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
            }

            CountryList(model: model, onOpenReport: onOpenReport)
        }
    }
}

private struct StatusBanner: View {

    let report: AvailabilityReport

    private var tint: Color {
        switch report.verdict {
        case .live: .green
        case .notLiveAnywhere: .red
        case .notFoundYet: .orange
        }
    }

    private var symbol: String {
        switch report.verdict {
        case .live: "checkmark.circle.fill"
        case .notLiveAnywhere: "xmark.circle.fill"
        case .notFoundYet: "questionmark.circle.fill"
        }
    }

    private var headline: String {
        switch report.verdict {
        case .live: "Live"
        case .notLiveAnywhere: "Not live anywhere"
        case .notFoundYet: "Not found yet"
        }
    }

    private var detail: String {
        let checked = report.results.count
        return switch report.verdict {
        case .live:
            "On sale in \(report.live.count) of \(checked) storefronts checked."
        case .notLiveAnywhere:
            "None of the \(checked) storefronts list this app. It may be removed, unreleased, or the ID is wrong."
        case .notFoundYet:
            "Not listed in \(report.notLive.count) storefronts; \(report.unconfirmed.count) couldn't be confirmed."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if report.isPartial {
                    Text("Stopped early — \(Storefront.everywhere.count - report.results.count) storefronts weren't checked.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Checked \(report.checkedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if report.isLiveAnywhere {
                ShareLink(item: report.shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share list of live countries")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

private struct LiveAppCard: View {

    let app: AppStoreApp
    let storefront: Storefront
    let onOpenReport: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Live listing · \(storefront.flag) \(storefront.name)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            AppHeader(app: app)

            HStack(spacing: 10) {
                Button {
                    onOpenReport(String(app.trackId), storefront.code)
                } label: {
                    Label("Full report", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let link = app.trackViewUrl, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("App Store", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Country list

private struct CountryList: View {

    @Bindable var model: AvailabilityViewModel
    let onOpenReport: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Countries")

            Picker("Show", selection: $model.filter) {
                ForEach(AvailabilityFilter.allCases) { filter in
                    Text("\(filter.label) \(model.count(for: filter))").tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Filter countries", text: $model.countrySearch)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.card, in: .rect(cornerRadius: 10))

            if model.visibleItems.isEmpty {
                Text(model.countrySearch.isEmpty ? "Nothing in this group." : "No country matches “\(model.countrySearch)”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.visibleGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(group.region.label) · \(group.items.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, 44) }
                                CountryRow(item: item, onOpenReport: onOpenReport)
                            }
                        }
                        .background(Color.card, in: .rect(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct CountryRow: View {

    let item: StorefrontAvailability
    let onOpenReport: (String, String) -> Void

    var body: some View {
        if let app = item.app {
            Button {
                onOpenReport(String(app.trackId), item.storefront.code)
            } label: {
                row(app: app)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let link = app.trackViewUrl, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("Open in App Store", systemImage: "arrow.up.right.square")
                    }
                }
                Button {
                    onOpenReport(String(app.trackId), item.storefront.code)
                } label: {
                    Label("Full report for this storefront", systemImage: "doc.text.magnifyingglass")
                }
            }
        } else {
            row(app: nil)
        }
    }

    private func row(app: AppStoreApp?) -> some View {
        HStack(spacing: 10) {
            Text(item.storefront.flag)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.storefront.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if let app {
                    Text([app.priceLabel, app.version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let app {
                if let average = app.averageUserRating, let count = app.userRatingCount, count > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f ★", average))
                            .font(.caption.weight(.medium))
                        Text(count.formatted())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                } else {
                    Text("No ratings")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if item.isUnconfirmed {
                Text("No clean answer")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("Not sold")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

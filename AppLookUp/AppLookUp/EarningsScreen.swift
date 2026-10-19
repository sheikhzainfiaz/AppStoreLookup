//
//  EarningsScreen.swift
//  Applookup
//
//  v2: the Earnings tab — actual monthly earnings from App Store Connect.
//

import Charts
import SwiftUI
import UniformTypeIdentifiers

struct EarningsScreen: View {

    @Bindable var earnings: EarningsModel
    /// (query, storefront code) → open the full report in the Lookup tab.
    let onOpenReport: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !earnings.isConfigured {
                        ConnectCard(earnings: earnings)
                    } else {
                        if let message = earnings.errorMessage {
                            MessageBox(text: message, symbol: "exclamationmark.triangle")
                        }

                        if earnings.months.isEmpty && earnings.isLoading {
                            ProgressView("Loading reports…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                        } else if !earnings.months.isEmpty {
                            MonthOverview(earnings: earnings)
                            AppBreakdown(earnings: earnings, onOpenReport: onOpenReport)
                            SourceNote(earnings: earnings)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("Earnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if earnings.isConfigured {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            earnings.showingSetup = true
                        } label: {
                            Image(systemName: "key")
                        }
                        .accessibilityLabel("App Store Connect key")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await earnings.load() }
                        } label: {
                            if earnings.isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(earnings.isLoading)
                        .accessibilityLabel("Reload")
                    }
                }
            }
            .refreshable { await earnings.load() }
            .task {
                if earnings.isConfigured, earnings.months.isEmpty {
                    await earnings.load()
                }
            }
            .sheet(isPresented: $earnings.showingSetup) {
                ASCSetupSheet(earnings: earnings)
            }
            .navigationDestination(for: String.self) { key in
                AppEarningsDetail(earnings: earnings, key: key, onOpenReport: onOpenReport)
            }
        }
    }
}

// MARK: - Not connected

private struct ConnectCard: View {

    let earnings: EarningsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text("Your real monthly earnings")
                .font(.title3.weight(.semibold))

            Text("Apple publishes no earnings for any app. The actual numbers live in App Store Connect, for the apps your team owns. Connect an API key and this tab shows what each of your apps earned, month by month — and the Lookup tab uses those figures to calibrate earnings estimates for competitors.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                earnings.showingSetup = true
            } label: {
                Label("Connect App Store Connect", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Overview

private struct MonthOverview: View {

    @Bindable var earnings: EarningsModel

    private struct Bar: Identifiable {
        let key: String
        let label: String
        let usd: Double
        var id: String { key }
    }

    /// Oldest first, for the chart.
    private var bars: [Bar] {
        earnings.months.reversed().compactMap { month in
            earnings.totalProceedsUSD(month).map { Bar(key: month.key, label: month.shortLabel, usd: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let month = earnings.selectedMonth {
                Totals(earnings: earnings, month: month)
            }

            if !bars.isEmpty {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Month", bar.label),
                        y: .value("Earnings", bar.usd)
                    )
                    .foregroundStyle(bar.key == earnings.selectedMonthKey ? Color.accentColor : Color.accentColor.opacity(0.35))
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: "USD").notation(.compactName))
                            }
                        }
                    }
                }
                .frame(height: 170)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(earnings.months) { month in
                        let isActive = month.key == earnings.selectedMonthKey
                        Button {
                            earnings.selectedMonthKey = month.key
                        } label: {
                            Text(month.shortLabel)
                                .font(.caption.weight(isActive ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isActive ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary),
                                    in: .capsule
                                )
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .opacity(month.isLoaded ? 1 : 0.5)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }

    private struct Totals: View {

        let earnings: EarningsModel
        let month: EarningsMonth

        private var change: Double? {
            guard
                let previous = earnings.previousMonth,
                let now = earnings.totalProceedsUSD(month),
                let before = earnings.totalProceedsUSD(previous),
                before > 0
            else { return nil }
            return (now - before) / before
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(month.longLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch month.state {
                case .loading:
                    ProgressView().padding(.vertical, 8)
                case let .notReady(detail):
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                case let .failed(detail):
                    Label(detail, systemImage: "xmark.circle").font(.subheadline).foregroundStyle(.secondary)
                case .loaded, .noSales:
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(earnings.totalProceedsUSD(month).map { formatUSD($0) } ?? "—")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        if let change {
                            Text(change, format: .percent.precision(.fractionLength(0)).sign(strategy: .always()))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(change >= 0 ? .green : .red)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Earnings after Apple's cut")
                        if let gross = earnings.totalGrossUSD(month), gross > 0 {
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(formatUSD(gross)) gross sales")
                        }
                        Text("·").foregroundStyle(.tertiary)
                        Text("\(Int(earnings.totalDownloads(month)).formatted()) downloads")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

// MARK: - Per app

private struct AppBreakdown: View {

    let earnings: EarningsModel
    let onOpenReport: (String, String) -> Void

    private var apps: [(app: AppEarnings, usd: Double?)] {
        (earnings.selectedMonth?.apps ?? [])
            .map { (app: $0, usd: earnings.usd($0.proceeds)) }
            .sorted { ($0.usd ?? 0, $0.app.downloads) > ($1.usd ?? 0, $1.app.downloads) }
    }

    private var top: Double { max(apps.first?.usd ?? 1, 1) }

    var body: some View {
        if let month = earnings.selectedMonth, month.isLoaded {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("By app · \(month.longLabel)")

                if apps.isEmpty {
                    Text("No sales, downloads or in-app purchases that month.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(apps.enumerated()), id: \.element.app.id) { index, entry in
                            if index > 0 { Divider().padding(.leading, 60) }
                            NavigationLink(value: entry.app.key) {
                                AppEarningsRow(
                                    app: entry.app,
                                    usd: entry.usd,
                                    share: (entry.usd ?? 0) / top,
                                    listing: entry.app.appleID.flatMap { earnings.listings[$0] }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.card, in: .rect(cornerRadius: 14))
                }
            }
        }
    }
}

private struct AppEarningsRow: View {

    let app: AppEarnings
    let usd: Double?
    let share: Double
    let listing: AppStoreApp?

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(url: listing?.artworkURL, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(listing?.trackName ?? app.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(4, 110 * share), height: 5)

                Text("\(Int(app.downloads).formatted()) downloads")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(usd.map { formatUSD($0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct AppIcon: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
    }
}

private struct SourceNote: View {
    let earnings: EarningsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From App Store Connect Sales and Trends (monthly summary). Earnings are developer proceeds: units × proceeds per unit, after Apple's commission and before tax adjustments. Other currencies are converted to USD at today's rates, so totals are close to — not identical to — what Apple pays out. The Payments and Financial Reports page is the final word on payouts.")
            if let loaded = earnings.lastLoaded {
                Text("Updated \(loaded.formatted(.relative(presentation: .named))).")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - App detail

private struct AppEarningsDetail: View {

    let earnings: EarningsModel
    let key: String
    let onOpenReport: (String, String) -> Void

    private var history: [(month: EarningsMonth, app: AppEarnings?)] { earnings.history(for: key) }

    private var current: AppEarnings? {
        earnings.selectedMonth?.apps.first { $0.key == key }
    }

    private var anyEntry: AppEarnings? {
        current ?? history.compactMap(\.app).first
    }

    private var listing: AppStoreApp? {
        anyEntry?.appleID.flatMap { earnings.listings[$0] }
    }

    private struct Point: Identifiable {
        let key: String
        let label: String
        let usd: Double
        var id: String { key }
    }

    private var points: [Point] {
        history.reversed().compactMap { entry -> Point? in
            guard entry.month.isLoaded else { return nil }
            let usd = entry.app.flatMap { earnings.usd($0.proceeds) } ?? 0
            return Point(key: entry.month.key, label: entry.month.shortLabel, usd: usd)
        }
    }

    private var countries: [(code: String, usd: Double, downloads: Double)] {
        guard let current else { return [] }
        let codes = Set(current.proceedsByCountry.keys).union(current.downloadsByCountry.keys)
        return codes
            .map { code in
                (
                    code: code,
                    usd: earnings.usd(current.proceedsByCountry[code] ?? [:]) ?? 0,
                    downloads: current.downloadsByCountry[code] ?? 0
                )
            }
            .sorted { ($0.usd, $0.downloads) > ($1.usd, $1.downloads) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    AppIcon(url: listing?.artworkURL, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing?.trackName ?? anyEntry?.title ?? key)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                        if let id = anyEntry?.appleID {
                            Text("Apple ID \(String(id))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if points.count > 1 {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Monthly earnings")
                        Chart(points) { point in
                            LineMark(x: .value("Month", point.label), y: .value("Earnings", point.usd))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", point.label), y: .value("Earnings", point.usd))
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(amount, format: .currency(code: "USD").notation(.compactName))
                                    }
                                }
                            }
                        }
                        .frame(height: 160)
                    }
                    .padding(20)
                    .background(Color.card, in: .rect(cornerRadius: 14))
                }

                if let current, let month = earnings.selectedMonth {
                    ReportSection(month.longLabel) {
                        DetailRows(rows: rows(for: current))
                    }
                } else if let month = earnings.selectedMonth {
                    Text("Nothing for this app in \(month.longLabel).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !countries.isEmpty {
                    ReportSection("By storefront") {
                        VStack(spacing: 0) {
                            ForEach(Array(countries.prefix(25).enumerated()), id: \.element.code) { index, country in
                                if index > 0 { Divider().padding(.leading, 44) }
                                HStack(spacing: 10) {
                                    Text(Storefront.named(country.code).flag).frame(width: 24)
                                    Text(Storefront.named(country.code).name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text("\(Int(country.downloads).formatted()) dl")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatUSD(country.usd))
                                        .font(.subheadline.weight(.medium))
                                        .frame(minWidth: 70, alignment: .trailing)
                                }
                                .monospacedDigit()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                            if countries.count > 25 {
                                Text("+\(countries.count - 25) more storefronts")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                            }
                        }
                        .background(Color.card, in: .rect(cornerRadius: 14))
                    }
                }

                if let id = anyEntry?.appleID {
                    Button {
                        onOpenReport(String(id), earnings.topCountry(for: id) ?? "us")
                    } label: {
                        Label("Open App Store report", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .background(Color.surface)
        .navigationTitle(listing?.trackName ?? anyEntry?.title ?? "App")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rows(for app: AppEarnings) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Earnings", earnings.usd(app.proceeds).map { formatUSD($0, cents: true) } ?? "—"))
        if let gross = earnings.usd(app.gross), gross != 0 {
            rows.append(("Gross sales", formatUSD(gross, cents: true)))
        }
        if let iap = earnings.usd(app.inAppProceeds), iap != 0 {
            rows.append(("In-app purchases", formatUSD(iap, cents: true)))
        }
        if let subscriptions = earnings.usd(app.subscriptionProceeds), subscriptions != 0 {
            rows.append(("Subscriptions", formatUSD(subscriptions, cents: true)))
        }
        rows.append(("Downloads", Int(app.downloads).formatted()))
        if app.redownloads > 0 { rows.append(("Re-downloads", Int(app.redownloads).formatted())) }
        if app.updates > 0 { rows.append(("Updates", Int(app.updates).formatted())) }
        if app.downloads > 0, let usd = earnings.usd(app.proceeds), usd > 0 {
            rows.append(("Per download", formatUSD(usd / app.downloads, cents: true)))
        }
        let currencies = app.proceeds.filter { $0.value != 0 }.count
        if currencies > 1 { rows.append(("Paid in", "\(currencies) currencies")) }
        return rows
    }
}

private struct DetailRows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 16) }
                HStack {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Setup

private struct ASCSetupSheet: View {

    let earnings: EarningsModel
    @Environment(\.dismiss) private var dismiss

    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var vendorNumber = ""
    @State private var privateKey = ""
    @State private var importing = false
    @State private var error: String?
    @State private var confirmingDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section {
                    Text("Create a key in App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys. Give it the Sales or Finance role — it only needs to read reports. The .p8 file can be downloaded once, so keep a copy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                SwiftUI.Section("Key") {
                    TextField("Issuer ID", text: $issuerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    TextField("Key ID", text: $keyID)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }

                SwiftUI.Section {
                    TextField("Vendor number", text: $vendorNumber)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Vendor number")
                } footer: {
                    Text("Shown in Payments and Financial Reports, top left, under your team name.")
                }

                SwiftUI.Section {
                    TextEditor(text: $privateKey)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .overlay(alignment: .topLeading) {
                            if privateKey.isEmpty {
                                Text(earnings.hasPrivateKey
                                     ? "Key stored in Keychain. Paste a new one to replace it."
                                     : "Paste the contents of AuthKey_XXXXXXXXXX.p8")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button {
                        importing = true
                    } label: {
                        Label("Import .p8 file", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text("Stored in this device's Keychain. It never leaves the device except to sign requests to Apple.")
                }

                if let error {
                    SwiftUI.Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if earnings.isConfigured {
                    SwiftUI.Section {
                        Button("Disconnect and delete key", role: .destructive) {
                            confirmingDisconnect = true
                        }
                    }
                }
            }
            .navigationTitle("App Store Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(issuerID.isEmpty || keyID.isEmpty || vendorNumber.isEmpty
                                  || (privateKey.isEmpty && !earnings.hasPrivateKey))
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .plainText, .data]
            ) { result in
                importKey(result)
            }
            .confirmationDialog("Delete the stored key?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    earnings.disconnect()
                    dismiss()
                }
            }
            .onAppear {
                issuerID = earnings.issuerID
                keyID = earnings.keyID
                vendorNumber = earnings.vendorNumber
            }
        }
    }

    private func save() {
        do {
            try earnings.saveCredentials(
                issuerID: issuerID,
                keyID: keyID,
                vendorNumber: vendorNumber,
                privateKey: privateKey.isEmpty ? nil : privateKey
            )
            dismiss()
            Task { await earnings.load() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importKey(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                privateKey = text
                error = nil
                // AuthKey_ABC123XYZ.p8 carries the Key ID in its name.
                let name = url.deletingPathExtension().lastPathComponent
                if keyID.isEmpty, name.hasPrefix("AuthKey_") {
                    keyID = String(name.dropFirst("AuthKey_".count))
                }
            } else {
                error = "Couldn't read that file."
            }
        case let .failure(failure):
            error = failure.localizedDescription
        }
    }
}

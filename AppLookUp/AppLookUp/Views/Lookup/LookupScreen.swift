import SwiftUI

struct LookupScreen: View {

    @Bindable var model: LookupViewModel
    let onFindWhereLive: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SearchBar(model: model)

                    if let message = model.errorMessage {
                        VStack(alignment: .leading, spacing: 12) {
                            MessageBox(text: message, symbol: "exclamationmark.triangle")

                            if model.lastLookupWasNotFound {
                                Button(action: onFindWhereLive) {
                                    Label("Check every storefront for this app", systemImage: "globe")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    } else if model.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if let app = model.app {
                        AppReport(app: app, model: model)
                            .transition(.opacity)
                    } else {
                        StartHint()
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("App Store Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.snappy, value: model.app?.trackId)
            .sheet(isPresented: $model.showingCalibration) {
                CalibrationSheet(model: model)
            }
            .sheet(item: $model.inspection) { inspection in
                CountrySheet(storefront: inspection.storefront, model: model)
            }
        }
    }
}

// MARK: - Search

private struct SearchBar: View {

    @Bindable var model: LookupViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("App ID, bundle ID, or App Store link", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { Task { await model.submit() } }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    #endif

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

            HStack(spacing: 12) {
                Picker("Storefront", selection: $model.country) {
                    ForEach(Storefront.everywhere) { store in
                        Text("\(store.flag)  \(store.name)").tag(store.code)
                    }
                }
                .labelsHidden()
                .onChange(of: model.country) {
                    Task { await model.countryChanged() }
                }

                Spacer()

                Button("Look up") {
                    focused = false
                    Task { await model.submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSubmit)
            }
        }
    }
}

private struct StartHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste anything that identifies an app.")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ExampleRow(label: "Numeric ID", value: "904237743")
                ExampleRow(label: "Bundle ID", value: "com.culturedcode.ThingsiPhone")
                ExampleRow(label: "Store link", value: "apps.apple.com/us/app/things-3/id904237743")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}

private struct ExampleRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}


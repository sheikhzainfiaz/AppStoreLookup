import SwiftUI

// MARK: - Country detail

struct CountrySheet: View {

    let storefront: Storefront
    let model: LookupViewModel
    @Environment(\.dismiss) private var dismiss

    /// Read through the model so the sheet keeps updating after it's presented —
    /// `.sheet(item:)` hands you a snapshot, not a live value.
    private var inspection: StorefrontInspection {
        model.inspection ?? StorefrontInspection(storefront: storefront)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if inspection.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    } else if let failure = inspection.failure {
                        MessageBox(text: failure, symbol: "xmark.circle")
                    } else if let app = inspection.app {
                        AppHeader(app: app)

                        HStack(alignment: .top, spacing: 0) {
                            RatingBlock(
                                title: "All versions",
                                average: app.averageUserRating,
                                count: app.userRatingCount
                            )
                            Divider().frame(height: 62)
                            RatingBlock(
                                title: "Version \(app.version ?? "current")",
                                average: app.averageUserRatingForCurrentVersion,
                                count: app.userRatingCountForCurrentVersion
                            )
                        }
                        .padding(.vertical, 16)
                        .background(Color.card, in: .rect(cornerRadius: 14))

                        ReportSection("Local listing") {
                            DetailGrid(app: app)
                        }

                        if let notes = app.releaseNotes, !notes.isEmpty {
                            ReportSection("What's new here") { ExpandableText(notes) }
                        }

                        Button {
                            Task { await model.makePrimary(storefront) }
                        } label: {
                            Label("Use this storefront", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
            }
            .background(Color.surface)
            .navigationTitle("\(storefront.flag)  \(storefront.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}


import SwiftUI

// MARK: - Details

struct DetailGrid: View {

    let app: AppStoreApp

    private var rows: [(String, String)] {
        var rows: [(String, String)] = []

        if let version = app.version { rows.append(("Version", version)) }
        if let updated = app.updatedOn {
            rows.append(("Updated", updated.formatted(date: .abbreviated, time: .omitted)))
        }
        if let released = app.releasedOn {
            rows.append(("First released", released.formatted(date: .abbreviated, time: .omitted)))
        }
        if let size = app.fileSize {
            rows.append(("Size", size.formatted(.byteCount(style: .file))))
        }
        if let minimum = app.minimumOsVersion { rows.append(("Requires", "iOS \(minimum) or later")) }
        rows.append(("Price", app.priceLabel))
        if let genres = app.genres, !genres.isEmpty {
            rows.append(("Categories", genres.joined(separator: ", ")))
        }
        if let seller = app.sellerName { rows.append(("Seller", seller)) }
        if let bundle = app.bundleId { rows.append(("Bundle ID", bundle)) }
        rows.append(("Track ID", String(app.trackId)))

        let languages = app.languageNames
        if !languages.isEmpty {
            let shown = languages.prefix(6).joined(separator: ", ")
            let extra = languages.count > 6 ? " +\(languages.count - 6) more" : ""
            rows.append(("Languages", shown + extra))
        }
        let devices = app.deviceFamilies
        if !devices.isEmpty { rows.append(("Devices", devices.joined(separator: ", "))) }

        if let advisories = app.advisories, !advisories.isEmpty {
            rows.append(("Advisories", advisories.joined(separator: ", ")))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 116) }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)
                    Text(row.1)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 16)
            }
        }
        .background(Color.card, in: .rect(cornerRadius: 14))
    }
}


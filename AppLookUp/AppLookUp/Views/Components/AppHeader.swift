import SwiftUI

struct AppHeader: View {

    let app: AppStoreApp

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: app.artworkURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 20).fill(.quaternary)
            }
            .frame(width: 96, height: 96)
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(.separator, lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(app.trackName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)

                Text(app.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Tag(app.priceLabel)
                    if let genre = app.primaryGenreName { Tag(genre) }
                    if let age = app.contentAdvisoryRating { Tag(age) }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }
}

struct AppIcon: View {
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


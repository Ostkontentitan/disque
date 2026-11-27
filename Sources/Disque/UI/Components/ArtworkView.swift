import SwiftUI

/// Square artwork with a generated placeholder, loaded asynchronously and cached.
struct ArtworkView: View {
    let request: ArtworkRequest?
    var pixelSize: Int = 400
    var cornerRadius: CGFloat = 4
    var circular = false
    var placeholderText: String?

    var body: some View {
        ArtworkFill(request: request, pixelSize: pixelSize, placeholderText: placeholderText)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

/// Fills whatever frame it is given with the artwork (cropping as needed).
struct ArtworkFill: View {
    let request: ArtworkRequest?
    var pixelSize: Int = 400
    var placeholderText: String?

    @State private var image: NSImage?

    init(request: ArtworkRequest?, pixelSize: Int = 400, placeholderText: String? = nil) {
        self.request = request
        self.pixelSize = pixelSize
        self.placeholderText = placeholderText
        _image = State(initialValue: request.flatMap { ArtworkLoader.shared.cachedImage(for: $0, pixelSize: pixelSize) })
    }

    var body: some View {
        placeholder
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: taskKey) { await load() }
    }

    private var taskKey: String { "\(request?.key ?? "-")@\(pixelSize)" }

    private var placeholder: some View {
        Rectangle()
            .fill(Theme.placeholderGradient(seed: request?.seed ?? placeholderText ?? ""))
            .overlay {
                GeometryReader { proxy in
                    Group {
                        if let placeholderText, !placeholderText.initials.isEmpty {
                            Text(placeholderText.initials)
                                .font(.system(size: proxy.size.width * 0.32, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: proxy.size.width * 0.3, weight: .light))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
    }

    private func load() async {
        guard let request else {
            image = nil
            return
        }
        if let cached = ArtworkLoader.shared.cachedImage(for: request, pixelSize: pixelSize) {
            image = cached
            return
        }
        image = nil
        let loaded = await ArtworkLoader.shared.image(for: request, pixelSize: pixelSize)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) { image = loaded }
    }
}

/// 2×2 mosaic of up to four album covers, used for playlists.
struct MosaicArtwork: View {
    let requests: [ArtworkRequest]
    var cornerRadius: CGFloat = 6
    var seed: String

    var body: some View {
        Group {
            if requests.count >= 4 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ArtworkFill(request: requests[0], pixelSize: 300)
                        ArtworkFill(request: requests[1], pixelSize: 300)
                    }
                    GridRow {
                        ArtworkFill(request: requests[2], pixelSize: 300)
                        ArtworkFill(request: requests[3], pixelSize: 300)
                    }
                }
            } else if let first = requests.first {
                ArtworkFill(request: first, pixelSize: 600)
            } else {
                Rectangle()
                    .fill(Theme.placeholderGradient(seed: seed))
                    .overlay {
                        GeometryReader { proxy in
                            Image(systemName: "music.note.list")
                                .font(.system(size: proxy.size.width * 0.28, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Large blurred artwork wash behind page headers.
struct HeroBackdrop: View {
    let request: ArtworkRequest?
    var height: CGFloat = 440

    var body: some View {
        ArtworkFill(request: request, pixelSize: 160)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .blur(radius: 70, opaque: true)
            .opacity(0.5)
            .overlay {
                // Fade in from the top bar and out into the page so the wash has no hard edges.
                LinearGradient(
                    stops: [
                        .init(color: Theme.background, location: 0),
                        .init(color: Theme.background.opacity(0.35), location: 0.22),
                        .init(color: Theme.background.opacity(0.55), location: 0.55),
                        .init(color: Theme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
            .allowsHitTesting(false)
    }
}

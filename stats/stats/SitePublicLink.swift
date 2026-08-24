import SwiftUI
import UIKit
import Photos

enum SitePublicLink {
    static let host = "https://idynkydnk.pythonanywhere.com"

    static func stats(section: GameSection, year: String) -> URL? {
        let y = normalizedYear(year)
        switch section {
        case .doubles: return page("stats", y)
        case .vollis: return page("vollis_stats", y)
        case .other: return page("other_stats", y)
        }
    }

    static func games(section: GameSection, year: String) -> URL? {
        let y = normalizedYear(year)
        switch section {
        case .doubles: return page("games", y)
        case .vollis: return page("vollis_games", y)
        case .other: return page("other_games", y)
        }
    }

    static func player(section: GameSection, year: String, name: String) -> URL? {
        let y = normalizedYear(year)
        switch section {
        case .doubles: return page("player", y, name)
        case .vollis: return page("vollis_player", y, name)
        case .other: return page("other_player", y, name)
        }
    }

    static func network(year: String) -> URL? {
        page("player_network", normalizedYear(year))
    }

    static func volleyball(year: String) -> URL? {
        page("volleyball_stats", normalizedYear(year))
    }

    static func recap(_ shareId: String) -> URL? {
        page("recap", shareId)
    }

    static func flyer(_ shareId: String) -> URL? {
        page("flyer", shareId)
    }

    static func flyerDownload(_ shareId: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = shareId.addingPercentEncoding(withAllowedCharacters: allowed) ?? shareId
        return URL(string: "\(host)/flyer/\(encoded)/download.jpg")
    }

    static func faceThumb(name: String, size: Int = 256) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return URL(string: "\(host)/player_face_thumb/\(encoded)?size=\(size)")
    }

    static func absolute(_ raw: String?) -> URL? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        let path = raw.hasPrefix("/") ? raw : "/\(raw)"
        return URL(string: host + path)
    }

    static func normalizedYear(_ raw: String) -> String {
        if raw.isEmpty || raw == "All" { return "All years" }
        return raw
    }

    private static func page(_ parts: String...) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
        return URL(string: host + "/" + encoded.joined(separator: "/") + "/")
    }
}

struct SiteCopyLinkButton: View {
    var url: URL?
    @State private var copied = false

    var body: some View {
        if let url {
            Button {
                UIPasteboard.general.string = url.absoluteString
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "link")
            }
            .accessibilityLabel(copied ? "Copied" : "Copy web link")
        }
    }
}

struct SitePhotoSaveError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Saves a flyer JPEG to the photo library so it can be shared from Photos.
struct SiteSaveFlyerPictureButton: View {
    var imageURL: URL
    @State private var working = false
    @State private var saved = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if working {
                        ProgressView()
                    } else if saved {
                        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 10)
                .background(saved ? Color.green.opacity(0.18) : SiteAddAccent.orange)
                .foregroundStyle(saved ? Color.green : Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(working)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func save() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: data) else {
                error = "Could not load picture"
                return
            }
            try await saveToLibrary(image)
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveToLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SitePhotoSaveError(message: "Allow Photos access in Settings to save flyers.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

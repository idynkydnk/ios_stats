import SwiftUI
import UIKit

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

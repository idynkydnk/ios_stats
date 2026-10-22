import Foundation

nonisolated struct SiteAccountDeletionResult: Decodable, Identifiable {
    var ok: Bool
    var appleManualRevocationRequired: Bool?
    var appleManualRevocationUrl: String?
    var id: String { "account-deleted" }
    var needsAppleInstructions: Bool { appleManualRevocationRequired == true }

    /// Keep this final account-management link on Apple's official support site.
    var appleHelpURL: URL {
        let fallback = URL(string: "https://support.apple.com/en-us/102571")!
        guard let raw = appleManualRevocationUrl, let url = URL(string: raw),
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "support.apple.com",
              (url.port ?? 443) == 443, url.user == nil, url.password == nil else { return fallback }
        return url
    }
}

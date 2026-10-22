import Foundation

@main
struct AccountDeletionTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let standard = try decoder.decode(SiteAccountDeletionResult.self, from: Data(#"{"ok":true,"apple_manual_revocation_required":false}"#.utf8))
        precondition(standard.ok && !standard.needsAppleInstructions)
        let legacy = try decoder.decode(SiteAccountDeletionResult.self, from: Data(#"{"ok":true,"apple_manual_revocation_required":true,"apple_manual_revocation_url":"https://support.apple.com/en-us/102571"}"#.utf8))
        precondition(legacy.ok && legacy.needsAppleInstructions)
        precondition(legacy.appleHelpURL.absoluteString == "https://support.apple.com/en-us/102571")
        let olderResponse = try decoder.decode(SiteAccountDeletionResult.self, from: Data(#"{"ok":true}"#.utf8))
        precondition(olderResponse.ok && !olderResponse.needsAppleInstructions)
        for unsafe in ["http://support.apple.com/help", "https://support.apple.com.evil.test/help", "https://support.apple.com:444/help", "javascript:alert(1)", "https://user:pass@support.apple.com/help"] {
            let result = SiteAccountDeletionResult(ok: true, appleManualRevocationRequired: true, appleManualRevocationUrl: unsafe)
            precondition(result.appleHelpURL.absoluteString == "https://support.apple.com/en-us/102571")
        }
        do {
            _ = try decoder.decode(SiteAccountDeletionResult.self, from: Data(#"{"error":"not deleted"}"#.utf8))
            preconditionFailure("Missing success state must not be treated as a deletion")
        } catch is DecodingError { }
        print("Account deletion: normal, legacy Apple fallback, safe help links, and malformed responses passed")
    }
}

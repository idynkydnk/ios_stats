import Foundation

@main
struct WebAuthenticationTests {
    static func main() {
        let origin = URL(string: "https://stats.example")!
        let allowed = ["https://stats.example/recap/abc/", "https://stats.example:443/flyer/abc/", "https://STATS.example/privacy"]
        for raw in allowed {
            let request = SiteWebAuthentication.request(URL(string: raw)!, baseURL: origin, token: "test-token")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            precondition(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
        let rejected = ["http://stats.example/recap/abc/", "https://stats.example:444/", "https://stats.example.attacker.test/", "https://elsewhere.example/", "file:///tmp/stats.example", "https://stats.example@elsewhere.example/"]
        for raw in rejected {
            let url = URL(string: raw)!
            precondition(!SiteWebAuthentication.isSameOrigin(url, as: origin))
            precondition(SiteWebAuthentication.request(url, baseURL: origin, token: "test-token").value(forHTTPHeaderField: "Authorization") == nil)
        }
        for token in [nil, ""] as [String?] {
            precondition(SiteWebAuthentication.request(origin, baseURL: origin, token: token).value(forHTTPHeaderField: "Authorization") == nil)
        }
        var form = URLRequest(url: origin.appendingPathComponent("admin/content-reports"))
        form.httpMethod = "POST"
        form.httpBody = Data("action=dismiss&csrf=example".utf8)
        form.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let signedForm = SiteWebAuthentication.request(form, baseURL: origin, token: "admin-token")
        precondition(signedForm.httpMethod == "POST" && signedForm.httpBody == form.httpBody)
        precondition(signedForm.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        precondition(signedForm.value(forHTTPHeaderField: "Authorization") == "Bearer admin-token")
        form.url = URL(string: "https://elsewhere.example/")
        form.setValue("Bearer stale-token", forHTTPHeaderField: "Authorization")
        precondition(SiteWebAuthentication.request(form, baseURL: origin, token: "admin-token").value(forHTTPHeaderField: "Authorization") == nil)
        var decisions: [Bool] = []
        let accepted = SiteWebConfirmation { decisions.append($0) }
        accepted.finish(true)
        accepted.finish(false)
        precondition(decisions == [true], "An accepted action must not also be cancelled")
        let cancelled = SiteWebConfirmation { decisions.append($0) }
        cancelled.finish(false)
        cancelled.finish(true)
        precondition(decisions == [true, false], "Cancellation must reject late acceptance")
        do {
            let abandoned = SiteWebConfirmation { decisions.append($0) }
            withExtendedLifetime(abandoned) { }
        }
        precondition(decisions == [true, false, false], "Abandoned presentations must finish as cancellation")
        print("Web authentication origin and credential checks passed")
    }
}

import SwiftUI
import WebKit

struct SiteRecapPageView: View {
    @Environment(\.siteAppearance) private var appearance
    @ScaledMetric(relativeTo: .body) private var readingSize = 17.0
    var title: String
    var url: URL
    @State private var loading = true
    @State private var loadError: String?
    @State private var currentURL: URL?
    @State private var reloadID = UUID()

    var body: some View {
        ZStack {
            SiteInAppWebView(url: url, appearance: appearance, readingSize: readingSize,
                             isLoading: $loading, loadError: $loadError, currentURL: $currentURL)
                .id(reloadID)
            if loading {
                ProgressView("Loading recap…")
                    .padding(20)
                    .background(appearance.panel, in: RoundedRectangle(cornerRadius: appearance.style.radius(16)))
            }
        }
        .background(appearance.background)
        .navigationTitle((currentURL ?? url).path.hasPrefix("/recap/") ? "AI Recap" : title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(appearance.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SiteCopyLinkButton(url: currentURL ?? url, showsTitle: true, isPublicLink: true)
                    .labelStyle(.titleAndIcon)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let loadError {
                HStack {
                    Text(loadError).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Try again") { reloadID = UUID() }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
    }
}

private struct SiteInAppWebView: UIViewRepresentable {
    var url: URL
    var appearance: SiteAppearance
    var readingSize: Double
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    @Binding var currentURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadError: $loadError, currentURL: $currentURL)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(appearance.background)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.applyStyle(readerScript, to: web)
        context.coordinator.load(url, in: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.backgroundColor = UIColor(appearance.background)
        uiView.scrollView.backgroundColor = uiView.backgroundColor
        context.coordinator.applyStyle(readerScript, to: uiView)
        context.coordinator.load(url, in: uiView)
    }

    private var readerScript: String {
        SiteRecapReaderStyle.script(appearance: appearance, readingSize: readingSize)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var isLoading: Binding<Bool>
        var loadError: Binding<String?>
        var currentURL: Binding<URL?>
        private var loadedURL: URL?
        private var styleScript: String?

        func applyStyle(_ script: String, to webView: WKWebView) {
            guard styleScript != script else { return }
            styleScript = script
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        init(isLoading: Binding<Bool>, loadError: Binding<String?>, currentURL: Binding<URL?>) {
            self.isLoading = isLoading
            self.loadError = loadError
            self.currentURL = currentURL
        }

        func load(_ url: URL, in webView: WKWebView) {
            if loadedURL == url { return }
            loadedURL = url
            isLoading.wrappedValue = true
            loadError.wrappedValue = nil
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            currentURL.wrappedValue = webView.url
            isLoading.wrappedValue = false
            loadError.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            currentURL.wrappedValue = webView.url
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            loadError.wrappedValue = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
            loadError.wrappedValue = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if ["http", "https", "about"].contains(scheme) {
                if navigationAction.targetFrame == nil {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

import SwiftUI
import WebKit

struct SiteRecapPageView: View {
    var title: String
    var url: URL
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            SiteInAppWebView(url: url, isLoading: $loading, loadError: $loadError)
            if loading {
                ProgressView()
            }
        }
        .background(Color.black)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SiteCopyLinkButton(url: url, showsTitle: true)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

private struct SiteInAppWebView: UIViewRepresentable {
    var url: URL
    @Binding var isLoading: Bool
    @Binding var loadError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, loadError: $loadError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let hideChrome = WKUserScript(
            source: """
            (function() {
              var css = '.recap-share-bar,.recap-menu-fab{display:none!important;}';
              var style = document.createElement('style');
              style.id = 'stats-app-embed';
              style.appendChild(document.createTextNode(css));
              (document.head || document.documentElement).appendChild(style);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(hideChrome)

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.043, green: 0.059, blue: 0.078, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.load(url, in: web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.load(url, in: uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var isLoading: Binding<Bool>
        var loadError: Binding<String?>
        private var loadedURL: URL?

        init(isLoading: Binding<Bool>, loadError: Binding<String?>) {
            self.isLoading = isLoading
            self.loadError = loadError
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
            isLoading.wrappedValue = false
            loadError.wrappedValue = nil
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

import AppKit
import WebKit

/// claude.ai dentro de um WKWebView com armazenamento persistente próprio da conta,
/// então cada conta mantém seus cookies (e seu login) separados.
@MainActor
final class WebPane: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    static let home = URL(string: "https://claude.ai/")!
    // UA do Safari: o Google recusa login em web views com UA de "app embutido".
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    let webView: WKWebView
    @Published private(set) var canGoBack = false
    @Published private(set) var isLoading = false

    private var popups: [NSWindow] = []
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    init(storeID: UUID) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        // claude.ai segue o prefers-color-scheme: forçar escuro mantém o visual do app.
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.underPageBackgroundColor = Theme.nsBg
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: Self.home))
    }

    func goHome() { webView.load(URLRequest(url: Self.home)) }
    func reload() { webView.reload() }
    func goBack() { webView.goBack() }

    private func refreshState() {
        canGoBack = webView.canGoBack
        isLoading = webView.isLoading
    }

    /// Hosts que abrem dentro do app (login e o próprio Claude). O resto vai para o navegador padrão.
    private static func isInternal(_ url: URL?) -> Bool {
        guard let url else { return true }
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return true }
        guard let host = url.host?.lowercased() else { return true }
        let allowed = ["claude.ai", "claude.com", "anthropic.com", "google.com", "gstatic.com",
                       "apple.com", "cloudflare.com", "stripe.com", "stripe.network"]
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshState() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame == true, !Self.isInternal(url), let url {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = downloads.appendingPathComponent(suggestedFilename)
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            dest = downloads.appendingPathComponent(name)
            n += 1
        }
        downloadDestinations[ObjectIdentifier(download)] = dest
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let dest = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) {
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        if !Self.isInternal(url), let url {
            NSWorkspace.shared.open(url)
            return nil
        }
        // Popups (ex.: login) compartilham o mesmo armazenamento da conta.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popup.customUserAgent = Self.userAgent
        popup.uiDelegate = self
        popup.navigationDelegate = self
        let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.title = url?.host ?? "Login"
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups.append(window)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let window = popups.first(where: { $0.contentView === webView }) {
            window.close()
            popups.removeAll { $0 === window }
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        return panel.runModal() == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        origin.host.hasSuffix("claude.ai") ? .grant : .prompt
    }

    /// Apaga cookies e dados do claude.ai desta conta (faz logout do web).
    func clearData() async {
        let store = webView.configuration.websiteDataStore
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        goHome()
    }
}

import AppKit
import WebKit
import SwiftTerm

/// Depuração: com DUO_SNAPSHOT=/caminho.png no ambiente, salva um PNG da janela
/// principal alguns segundos após abrir (inclui o conteúdo dos WKWebViews).
@MainActor
enum Snapshot {
    static func scheduleIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["DUO_SNAPSHOT"] else { return }
        let delay = Double(ProcessInfo.processInfo.environment["DUO_SNAPSHOT_DELAY"] ?? "") ?? 6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { await capture(to: URL(fileURLWithPath: path)) }
        }
    }

    private static func capture(to url: URL) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0.contentView is WKWebView) }),
              let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for web in webViews(in: content) where !web.isHiddenOrHasHiddenAncestor {
            guard let image = try? await web.takeSnapshot(configuration: nil) else { continue }
            var rect = web.convert(web.bounds, to: content)
            if content.isFlipped { rect.origin.y = content.bounds.height - rect.maxY }
            image.draw(in: rect)
        }
        // O SwiftTerm desenha no conteúdo da layer, fora do draw(_:), então o cacheDisplay não pega.
        if let cg = NSGraphicsContext.current?.cgContext {
            for term in terminals(in: content) where !term.isHiddenOrHasHiddenAncestor {
                guard let layer = term.layer else { continue }
                var rect = term.convert(term.bounds, to: content)
                if content.isFlipped { rect.origin.y = content.bounds.height - rect.maxY }
                cg.saveGState()
                cg.translateBy(x: rect.minX, y: rect.maxY)
                cg.scaleBy(x: 1, y: -1)
                layer.render(in: cg)
                cg.restoreGState()
                let info = "frame=\(term.frame) firstResponder=\(term.window?.firstResponder === term)\n"
                let text = info + (String(data: term.getBufferAsData(), encoding: .utf8) ?? "")
                try? text.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func terminals(in view: NSView) -> [LocalProcessTerminalView] {
        if let term = view as? LocalProcessTerminalView { return [term] }
        return view.subviews.flatMap(terminals(in:))
    }

    private static func webViews(in view: NSView) -> [WKWebView] {
        if let web = view as? WKWebView { return [web] }
        return view.subviews.flatMap(webViews(in:))
    }
}

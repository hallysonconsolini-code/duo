import AppKit
import SwiftTerm

/// Soltar arquivos ou pastas do Finder no terminal digita os caminhos no prompt, sem Enter.
/// O Claude Code lê o arquivo pelo caminho (imagens, PDFs, qualquer coisa), então o conteúdo
/// não é enviado. Os caminhos saem escapados com barra invertida, como no Terminal.app, e
/// vêm por colagem (bracketed paste) para o Claude Code reconhecer o caminho como anexo.
///
/// O arrastar da barra do painel (zonas de encaixe) é tratado por um monitor de mouse e não
/// usa o sistema de drag do AppKit, então não disputa o drop com o terminal.
enum FileDrop {
    static let types: [NSPasteboard.PasteboardType] = [.fileURL]

    static func paths(from pasteboard: NSPasteboard) -> [String] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { $0.standardizedFileURL.path }
    }

    /// Caminhos separados por espaço, com um espaço no fim para o próximo texto não grudar.
    static func line(for paths: [String]) -> String {
        paths.map(escape).joined(separator: " ") + " "
    }

    /// Barra invertida antes de cada caractere especial do shell. Nome com quebra de linha não
    /// cabe em barra invertida; esse cai em aspas simples.
    static func escape(_ path: String) -> String {
        if path.contains(where: \.isNewline) {
            return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let special = Set(" \t!\"#$&'()*;<>?[\\]^`{|}~")
        var out = ""
        for ch in path {
            if special.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}

extension PaneTerminalView {
    func enableFileDrop() {
        registerForDraggedTypes(FileDrop.types)
    }

    private func acceptsDrag(_ info: NSDraggingInfo) -> Bool {
        !FileDrop.paths(from: info.draggingPasteboard).isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrag(sender) else { return [] }
        setDropHighlight(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptsDrag(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlight(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropHighlight(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptsDrag(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropHighlight(false)
        let paths = FileDrop.paths(from: sender.draggingPasteboard)
        guard !paths.isEmpty else { return false }
        window?.makeFirstResponder(self)
        pasteText(FileDrop.line(for: paths))
        return true
    }
}

import AppKit
import SwiftTerm

/// Terminal do painel. A janela do Duo é arrastável pelo fundo (titlebar oculta), e
/// por padrão o AppKit rouba o clique-e-arraste dentro do terminal para mover a
/// janela, o que impede selecionar texto com o mouse.
class PaneTerminalView: LocalProcessTerminalView {
    override var mouseDownCanMoveWindow: Bool { false }

    /// A seleção que o Cmd+A fez na caixa de prompt, para tirar as bordas da caixa
    /// ao copiar e para apagar o texto quando a próxima tecla pede isso.
    var promptSelection: (start: Position, end: Position)?

    override func copy(_ sender: Any?) {
        guard let text = promptSelectionText() else { return super.copy(sender) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Cmd+A nos painéis: seleciona só o texto que você está digitando na caixa de
/// prompt do Claude Code, em vez do terminal inteiro.
///
/// Sem caixa de prompt à vista — um shell comum, por exemplo — ou apertando
/// Cmd+A de novo em cima da mesma seleção, o atalho volta a selecionar tudo,
/// que é o comportamento padrão do SwiftTerm.
enum InputSelection {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let terminal = focusedTerminal() as? PaneTerminalView else { return event }
            if isSelectAll(event) {
                return terminal.selectCurrentInput() ? nil : event
            }
            return handleAfterSelection(event, in: terminal)
        }
    }

    private static func isSelectAll(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    /// A seleção do terminal é só visual: o Claude Code não sabe dela. Então, com o
    /// texto da caixa selecionado, as teclas que mexeriam na seleção num campo de
    /// texto normal viram apagar-e-digitar no input do Claude Code.
    private static func handleAfterSelection(_ event: NSEvent, in terminal: PaneTerminalView) -> NSEvent? {
        guard terminal.promptSelectionText() != nil else { return event }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "x" {
            terminal.copy(nil)
            _ = terminal.deletePromptSelection()
            return nil
        }
        // Cmd+C e afins: a própria cadeia de respondedores cuida.
        if flags.contains(.command) { return event }

        switch event.keyCode {
        case 51, 117: // delete e forward delete
            _ = terminal.deletePromptSelection()
            return nil
        case 36, 76: // return e enter: manda o que está escrito, não apaga
            terminal.clearPromptSelection()
            return event
        default:
            // Digitar em cima da seleção substitui o texto, como num campo de texto.
            // Setas, F1…F12 e teclas de função chegam como escalares reservados
            // (0xF700+): essas só desfazem a seleção.
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700
                  })
            else {
                terminal.clearPromptSelection()
                return event
            }
            _ = terminal.deletePromptSelection()
            return event
        }
    }

    /// O terminal em foco, seja ele o primeiro respondedor ou o dono dele.
    private static func focusedTerminal() -> LocalProcessTerminalView? {
        var view = NSApp.keyWindow?.firstResponder as? NSView
        while let current = view {
            if let terminal = current as? LocalProcessTerminalView { return terminal }
            view = current.superview
        }
        return nil
    }
}

extension LocalProcessTerminalView {
    /// O Claude Code já desenhou a caixa de prompt de duas formas: com bordas em
    /// volta ("│ > texto │") e com uma régua horizontal acima e abaixo ("❯ texto").
    fileprivate static let borders: Set<Character> = ["│", "┃", "┆", "┊", "║", "|"]
    fileprivate static let markers: Set<Character> = [">", "❯", "›", "»"]
    fileprivate static let ruleChars: Set<Character> = [
        "─", "━", "═", "╌", "╍", "┄", "┅", "┈", "┉", "-", "_",
        "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘", "├", "┤", "│", "┃", "║",
    ]

    /// Seleciona o texto da caixa de prompt visível. `false` quando não há caixa
    /// na tela, quando nada foi digitado ainda, ou quando essa mesma seleção já
    /// está ativa — nesses casos quem chamou deve seguir com o Cmd+A normal.
    func selectCurrentInput() -> Bool {
        // `terminal` e `selection` são internos ao SwiftTerm; a reflexão é a
        // única forma de chegar neles sem manter um fork da biblioteca.
        guard let terminal: Terminal = reflect(), let selection: SelectionService = reflect() else {
            Self.log("não achei o Terminal/SelectionService do SwiftTerm")
            return false
        }

        let range: (start: Position, end: Position)? = terminal.terminalLock.withLock {
            var cache: [Int: [Character]] = [:]
            func cells(_ row: Int) -> [Character] {
                if let hit = cache[row] { return hit }
                let line = (0..<terminal.cols).map { terminal.getCharacter(col: $0, row: row) ?? " " }
                cache[row] = line
                return line
            }

            // O texto que você está digitando é onde o cursor está. Daí sobe-se até
            // a linha que abre a caixa. Sem cursor na caixa, procura-se a última
            // caixa da tela, de baixo para cima.
            let cursorRow = min(max(terminal.buffer.y, 0), terminal.rows - 1)
            let cursorCol = terminal.buffer.x
            var prompt: (row: Int, col: Int)?
            var up = cursorRow
            while up >= 0, !Self.isRule(cells(up)) {
                if let col = Self.inputStart(in: cells(up)) {
                    prompt = (up, col)
                    break
                }
                up -= 1
            }
            if prompt == nil {
                for row in stride(from: terminal.rows - 1, through: 0, by: -1) {
                    if let col = Self.inputStart(in: cells(row)) {
                        prompt = (row, col)
                        break
                    }
                }
            }
            guard let prompt else {
                Self.log("nenhuma caixa de prompt na tela (cursor em \(cursorRow),\(cursorCol))")
                return nil
            }
            // Cursor na caixa e nada digitado ainda: deixa o Cmd+A normal passar.
            if cursorRow == prompt.row, cursorCol <= prompt.col {
                Self.log("caixa vazia")
                return nil
            }

            // Linhas seguintes, quando o texto digitado quebrou em várias.
            var lastRow = prompt.row
            if cursorRow > prompt.row, !Self.isRule(cells(cursorRow)) {
                lastRow = cursorRow
            } else {
                var row = prompt.row + 1
                while row < terminal.rows, Self.isContinuation(cells(row)) {
                    lastRow = row
                    row += 1
                }
            }
            // Despreza as linhas da caixa que ficaram vazias.
            while lastRow > prompt.row, Self.contentEnd(in: cells(lastRow), from: 0) == nil {
                lastRow -= 1
            }
            let from = lastRow == prompt.row ? prompt.col : 0
            guard let endCol = Self.contentEnd(in: cells(lastRow), from: from) else {
                Self.log("caixa sem texto digitado")
                return nil
            }

            let offset = terminal.buffer.yDisp
            return (Position(col: prompt.col, row: prompt.row + offset),
                    Position(col: endCol, row: lastRow + offset))
        }
        guard let range else { return false }

        // Cmd+A de novo em cima da mesma seleção: deixa passar para selecionar tudo.
        if selection.active, selection.start == range.start, selection.end == range.end {
            Self.log("mesma seleção de novo: segue o Cmd+A normal")
            return false
        }

        terminal.terminalLock.withLock {
            selection.setSelection(start: range.start, end: range.end)
        }
        (self as? PaneTerminalView)?.promptSelection = range
        needsDisplay = true
        return true
    }

    /// Apaga no input do Claude Code o texto que o Cmd+A selecionou, mandando um
    /// backspace por caractere — é o que o programa do terminal entende.
    func deletePromptSelection() -> Bool {
        guard let bytes = promptDeleteBytes() else { return false }
        clearPromptSelection()
        send(data: ArraySlice(bytes))
        return true
    }

    /// Os backspaces que apagam o texto selecionado: um por caractere. Quando o
    /// texto só quebrou linha por causa da largura da janela, sobram alguns — e
    /// backspace com o input já vazio não faz nada.
    func promptDeleteBytes() -> [UInt8]? {
        guard let text = promptSelectionText(), !text.isEmpty else { return nil }
        return [UInt8](repeating: backspaceSendsControlH ? 8 : 0x7f, count: text.count)
    }

    /// Desfaz a seleção do Cmd+A, tanto a marcação na tela quanto o estado guardado.
    func clearPromptSelection() {
        (self as? PaneTerminalView)?.promptSelection = nil
        guard let terminal: Terminal = reflect(), let selection: SelectionService = reflect() else { return }
        terminal.terminalLock.withLock { selection.selectNone() }
        needsDisplay = true
    }

    /// O texto da caixa de prompt sem as bordas que o SwiftTerm inclui quando a
    /// seleção passa de uma linha. nil quando a seleção atual não é a do Cmd+A.
    func promptSelectionText() -> String? {
        guard let pane = self as? PaneTerminalView,
              let saved = pane.promptSelection,
              let selection: SelectionService = reflect(),
              selection.active,
              selection.start == saved.start, selection.end == saved.end,
              let raw = getSelection()
        else { return nil }
        return Self.stripBorders(raw)
    }

    /// Tira a borda lateral das linhas de continuação ("│   resto do texto").
    fileprivate static func stripBorders(_ text: String) -> String {
        text.components(separatedBy: "\n").enumerated().map { index, line -> String in
            var chars = Array(line)
            while let last = chars.last, isBlank(last) { chars.removeLast() }
            if let last = chars.last, borders.contains(last) {
                chars.removeLast()
                while let last = chars.last, isBlank(last) { chars.removeLast() }
            }
            guard index > 0 else { return String(chars) }
            var i = 0
            while i < chars.count, isBlank(chars[i]) { i += 1 }
            guard i < chars.count, borders.contains(chars[i]) else { return String(chars) }
            i += 1
            while i < chars.count, isBlank(chars[i]) { i += 1 }
            return String(chars[i...])
        }.joined(separator: "\n")
    }

    /// Coluna onde começa o texto digitado numa linha de prompt ("❯ texto" ou
    /// "│ > texto"), ou nil se a linha não abre uma caixa de prompt.
    fileprivate static func inputStart(in line: [Character]) -> Int? {
        guard var i = line.firstIndex(where: { !isBlank($0) }) else { return nil }
        if borders.contains(line[i]) {
            i += 1
            while i < line.count, isBlank(line[i]) { i += 1 }
        }
        guard i < line.count, markers.contains(line[i]) else { return nil }
        i += 1
        // "> texto" e não ">>" nem ">" colado em outra coisa.
        guard i == line.count || isBlank(line[i]) else { return nil }
        while i < line.count, isBlank(line[i]) { i += 1 }
        return min(i, max(line.count - 1, 0))
    }

    /// A linha é uma régua da moldura ("────" ou "╰────╯"), o que fecha a caixa.
    fileprivate static func isRule(_ line: [Character]) -> Bool {
        let content = line.filter { !isBlank($0) }
        return !content.isEmpty && content.allSatisfy { ruleChars.contains($0) }
    }

    /// A linha continua o texto digitado: tem conteúdo, não é régua e não abre
    /// outra caixa de prompt.
    fileprivate static func isContinuation(_ line: [Character]) -> Bool {
        guard line.contains(where: { !isBlank($0) }) else { return false }
        return !isRule(line) && inputStart(in: line) == nil
    }

    /// Coluna logo depois do último caractere digitado, desprezando a borda
    /// direita e os espaços até ela. nil quando não há nada digitado.
    fileprivate static func contentEnd(in line: [Character], from start: Int) -> Int? {
        guard start < line.count else { return nil }
        var end = line.count
        func trim() { while end > start, isBlank(line[end - 1]) { end -= 1 } }
        trim()
        if end > start, borders.contains(line[end - 1]) {
            end -= 1
            trim()
        }
        return end > start ? end : nil
    }

    fileprivate static func isBlank(_ c: Character) -> Bool {
        c == "\0" || c == " " || c.isWhitespace
    }

    /// Com DUO_DEBUG_SELECTION no ambiente, conta no Console por que o Cmd+A não
    /// achou a caixa de prompt.
    fileprivate static let debugSelection = ProcessInfo.processInfo.environment["DUO_DEBUG_SELECTION"] != nil

    fileprivate static func log(_ message: String) {
        guard debugSelection else { return }
        NSLog("[duo cmd+a] %@", message)
    }

    private func reflect<T>() -> T? {
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                if let hit = child.value as? T { return hit }
            }
            mirror = current.superclassMirror
        }
        return nil
    }
}

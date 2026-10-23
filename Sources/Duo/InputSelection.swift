import AppKit
import SwiftTerm

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
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "a",
                  let terminal = focusedTerminal(),
                  terminal.selectCurrentInput()
            else { return event }
            return nil
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
    /// Bordas da caixa de prompt e marcadores de prompt que o Claude Code usa.
    fileprivate static let borders: Set<Character> = ["│", "┃", "┆", "┊", "║", "|"]
    fileprivate static let markers: Set<Character> = [">", "❯", "›", "»"]

    /// Seleciona o texto da caixa de prompt visível. `false` quando não há caixa
    /// na tela, quando nada foi digitado ainda, ou quando essa mesma seleção já
    /// está ativa — nesses casos quem chamou deve seguir com o Cmd+A normal.
    func selectCurrentInput() -> Bool {
        // `terminal` e `selection` são internos ao SwiftTerm; a reflexão é a
        // única forma de chegar neles sem manter um fork da biblioteca.
        guard let terminal: Terminal = reflect(), let selection: SelectionService = reflect() else {
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

            // A caixa do prompt fica na parte de baixo da tela.
            var prompt: (row: Int, col: Int)?
            for row in stride(from: terminal.rows - 1, through: 0, by: -1) {
                if let col = Self.inputStart(in: cells(row)) {
                    prompt = (row, col)
                    break
                }
            }
            guard let prompt else { return nil }

            // Linhas seguintes da mesma caixa, quando o texto quebrou em várias.
            var lastRow = prompt.row
            var row = prompt.row + 1
            while row < terminal.rows, Self.isBoxLine(cells(row)) {
                lastRow = row
                row += 1
            }
            // Despreza as linhas da caixa que ficaram vazias.
            while lastRow > prompt.row, Self.contentEnd(in: cells(lastRow), from: 0) == nil {
                lastRow -= 1
            }
            let from = lastRow == prompt.row ? prompt.col : 0
            guard let endCol = Self.contentEnd(in: cells(lastRow), from: from) else { return nil }

            let offset = terminal.buffer.yDisp
            return (Position(col: prompt.col, row: prompt.row + offset),
                    Position(col: endCol, row: lastRow + offset))
        }
        guard let range else { return false }

        // Cmd+A de novo em cima da mesma seleção: deixa passar para selecionar tudo.
        if selection.active, selection.start == range.start, selection.end == range.end {
            return false
        }

        terminal.terminalLock.withLock {
            selection.setSelection(start: range.start, end: range.end)
        }
        needsDisplay = true
        return true
    }

    /// Coluna onde começa o texto digitado numa linha "│ > texto", ou nil se a
    /// linha não abre uma caixa de prompt.
    fileprivate static func inputStart(in line: [Character]) -> Int? {
        guard var i = line.firstIndex(where: { !isBlank($0) }), borders.contains(line[i]) else {
            return nil
        }
        i += 1
        while i < line.count, isBlank(line[i]) { i += 1 }
        guard i < line.count, markers.contains(line[i]) else { return nil }
        // "> " e não ">>" nem "> " colado em outra coisa.
        guard i + 1 < line.count, isBlank(line[i + 1]) else { return nil }
        return min(i + 2, line.count - 1)
    }

    /// A linha ainda faz parte da caixa: começa com borda lateral, e não com o
    /// rodapé "╰────╯".
    fileprivate static func isBoxLine(_ line: [Character]) -> Bool {
        guard let i = line.firstIndex(where: { !isBlank($0) }) else { return false }
        return borders.contains(line[i])
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

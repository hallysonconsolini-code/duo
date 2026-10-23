import CoreGraphics

/// Posição de cada painel no grid, em células. Função pura: não sabe de SwiftUI.
///
/// Regras:
/// - colunas = max(maior colSpan, tabela de colunas aplicada à soma das áreas);
///   depois tira colunas enquanto isso não aumentar o número de linhas
///   (ex.: um painel alto + um normal ficam em 2 colunas, não em 3 com buracos);
/// - empacotamento denso na ordem dos painéis: cada um vai na primeira posição livre
///   onde cabe, e as linhas crescem se precisar;
/// - span maior que o número de colunas é limitado ao que cabe (o valor salvo não muda);
/// - no fim, buracos são preenchidos esticando um vizinho: primeiro o da esquerda,
///   na mesma linha; se não der, o de cima.
struct GridLayout: Equatable {
    struct Item: Equatable {
        var col: Int
        var row: Int
        var colSpan: Int
        var rowSpan: Int
    }

    let columns: Int
    let rows: Int
    /// Na mesma ordem dos spans recebidos.
    let items: [Item]

    static let empty = GridLayout(columns: 1, rows: 1, items: [])

    /// 1 → 1, 2 → 2, 3 → 3, 4 → 2x2, 5–9 → 3, depois 4 colunas.
    static func tableColumns(for count: Int) -> Int {
        switch count {
        case ...3: max(count, 1)
        case 4: 2
        case 5...9: 3
        default: 4
        }
    }

    static func make(spans: [(col: Int, row: Int)]) -> GridLayout {
        guard !spans.isEmpty else { return .empty }
        var spans = spans.map { (col: max($0.col, 1), row: max($0.row, 1)) }
        // Todos grandes é o mesmo que todos normais (senão dois grandes ficariam empilhados).
        if spans.allSatisfy({ $0.col >= 2 && $0.row >= 2 }) { spans = spans.map { _ in (col: 1, row: 1) } }
        let area = spans.reduce(0) { $0 + $1.col * $1.row }
        let widest = spans.map(\.col).max() ?? 1
        var columns = max(widest, tableColumns(for: area))
        var best = pack(spans, columns: columns)
        while columns > 1 {
            let narrower = pack(spans, columns: columns - 1)
            guard narrower.rows <= best.rows else { break }
            columns -= 1
            best = narrower
        }
        return best.stretched()
    }

    /// Empacotamento denso (como `grid-auto-flow: dense` do CSS).
    private static func pack(_ spans: [(col: Int, row: Int)], columns: Int) -> GridLayout {
        var occupied: [[Bool]] = []
        var items: [Item] = []
        func free(_ r: Int, _ c: Int, _ w: Int, _ h: Int) -> Bool {
            for rr in r..<(r + h) where rr < occupied.count {
                for cc in c..<(c + w) where occupied[rr][cc] { return false }
            }
            return true
        }
        for span in spans {
            let w = min(span.col, columns)
            let h = span.row
            var r = 0
            placing: while true {
                for c in 0...(columns - w) where free(r, c, w, h) {
                    while occupied.count < r + h { occupied.append(Array(repeating: false, count: columns)) }
                    for rr in r..<(r + h) { for cc in c..<(c + w) { occupied[rr][cc] = true } }
                    items.append(Item(col: c, row: r, colSpan: w, rowSpan: h))
                    break placing
                }
                r += 1
            }
        }
        return GridLayout(columns: columns, rows: max(occupied.count, 1), items: items)
    }

    /// Estica painéis para dentro dos buracos, sem mover ninguém.
    private func stretched() -> GridLayout {
        var items = self.items
        func owner(_ r: Int, _ c: Int) -> Int? {
            items.firstIndex { r >= $0.row && r < $0.row + $0.rowSpan && c >= $0.col && c < $0.col + $0.colSpan }
        }
        func isFree(_ r: Int, _ c: Int) -> Bool { owner(r, c) == nil }
        var changed = true
        while changed {
            changed = false
            for r in 0..<rows {
                for c in 0..<columns where isFree(r, c) {
                    // Vizinho da esquerda: cresce uma coluna se toda a borda direita dele estiver livre.
                    if c > 0, let i = owner(r, c - 1), items[i].col + items[i].colSpan == c,
                       (items[i].row..<(items[i].row + items[i].rowSpan)).allSatisfy({ isFree($0, c) }) {
                        items[i].colSpan += 1
                        changed = true
                        continue
                    }
                    // Vizinho de cima: cresce uma linha se toda a borda de baixo dele estiver livre.
                    if r > 0, let i = owner(r - 1, c), items[i].row + items[i].rowSpan == r,
                       (items[i].col..<(items[i].col + items[i].colSpan)).allSatisfy({ isFree(r, $0) }) {
                        items[i].rowSpan += 1
                        changed = true
                    }
                }
            }
        }
        return GridLayout(columns: columns, rows: rows, items: items).evenedLastRow(original: self.items)
    }

    /// Se a última linha só tem painéis de uma linha, todos pedidos com a mesma largura, mas
    /// que ficaram desiguais por causa do esticamento (ex.: 3 colunas e 2 painéis), divide a
    /// linha em partes iguais, como o grid antigo fazia. Para isso cada coluna vira `m`
    /// subcolunas, onde `m` é quantos painéis há na última linha.
    private func evenedLastRow(original: [Item]) -> GridLayout {
        let last = rows - 1
        let touching = items.indices.filter { items[$0].row + items[$0].rowSpan - 1 == last }
        guard touching.count > 1, touching.allSatisfy({ items[$0].row == last }),
              Set(touching.map { original[$0].colSpan }).count == 1,
              Set(touching.map { items[$0].colSpan }).count > 1 else { return self }
        let m = touching.count
        var scaled = items.map { Item(col: $0.col * m, row: $0.row, colSpan: $0.colSpan * m, rowSpan: $0.rowSpan) }
        for (k, i) in touching.sorted(by: { items[$0].col < items[$1].col }).enumerated() {
            scaled[i].col = k * columns
            scaled[i].colSpan = columns
        }
        return GridLayout(columns: columns * m, rows: rows, items: scaled)
    }

    /// Retângulo de cada célula/painel dentro de `size`, com espaçamento e margem.
    func frame(of item: Item, in size: CGSize, spacing: CGFloat, padding: CGFloat) -> CGRect {
        let cellW = max(0, (size.width - 2 * padding - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let cellH = max(0, (size.height - 2 * padding - CGFloat(rows - 1) * spacing) / CGFloat(rows))
        return CGRect(
            x: padding + CGFloat(item.col) * (cellW + spacing),
            y: padding + CGFloat(item.row) * (cellH + spacing),
            width: CGFloat(item.colSpan) * cellW + CGFloat(item.colSpan - 1) * spacing,
            height: CGFloat(item.rowSpan) * cellH + CGFloat(item.rowSpan - 1) * spacing
        )
    }
}

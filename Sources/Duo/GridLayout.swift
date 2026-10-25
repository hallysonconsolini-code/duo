import CoreGraphics

/// Posição de cada painel no grid, em células. Função pura: não sabe de SwiftUI.
///
/// Regras:
/// - colunas dependem só de quantos painéis há (tabela abaixo). O tamanho dos painéis nunca
///   muda o número de colunas: um span maior que o grid é limitado ao que cabe (o valor salvo
///   não muda), e as linhas crescem quando precisa;
/// - empacotamento denso na ordem dos painéis: cada um vai na primeira posição livre
///   onde cabe (linha por linha, da esquerda para a direita);
/// - ao redimensionar, o painel arrastado é posto primeiro no retângulo pedido e os outros
///   são empacotados em volta, na ordem deles (ver `resizing`);
/// - no fim, buracos são preenchidos esticando um vizinho: primeiro o da esquerda,
///   na mesma linha; se não der, o de cima.
struct GridLayout: Equatable {
    struct Item: Equatable {
        var col: Int
        var row: Int
        var colSpan: Int
        var rowSpan: Int

        var maxCol: Int { col + colSpan }
        var maxRow: Int { row + rowSpan }
    }

    typealias Span = (col: Int, row: Int)

    let columns: Int
    let rows: Int
    /// Na mesma ordem dos spans recebidos.
    let items: [Item]
    /// Larguras pedidas (antes de limitar e esticar), para dividir a última linha por igual.
    private(set) var requestedColSpans: [Int] = []

    static let empty = GridLayout(columns: 1, rows: 1, items: [])

    /// 1 → 1, 2 → 2, 3 → 3, 4 → 2x2, 5–9 → 3, depois 4 colunas.
    static func columns(for count: Int) -> Int {
        switch count {
        case ...3: max(count, 1)
        case 4: 2
        case 5...9: 3
        default: 4
        }
    }

    /// `columns` nil = pela tabela. `pinned`: painel que vai primeiro, numa posição fixa.
    static func make(spans: [Span], columns: Int? = nil, pinned: (index: Int, item: Item)? = nil) -> GridLayout {
        guard !spans.isEmpty else { return .empty }
        let columns = max(columns ?? Self.columns(for: spans.count), 1)
        let spans = spans.map { (col: min(max($0.col, 1), columns), row: max($0.row, 1)) }
        var layout = pack(spans, columns: columns, pinned: pinned).stretched()
        layout.requestedColSpans = spans.map(\.col)
        return layout
    }

    /// Empacotamento denso (como `grid-auto-flow: dense` do CSS).
    private static func pack(_ spans: [Span], columns: Int, pinned: (index: Int, item: Item)?) -> GridLayout {
        var occupied: [[Bool]] = []
        var items = spans.map { _ in Item(col: 0, row: 0, colSpan: 1, rowSpan: 1) }
        func free(_ r: Int, _ c: Int, _ w: Int, _ h: Int) -> Bool {
            for rr in r..<(r + h) where rr < occupied.count {
                for cc in c..<(c + w) where occupied[rr][cc] { return false }
            }
            return true
        }
        func occupy(_ item: Item) {
            while occupied.count < item.maxRow { occupied.append(Array(repeating: false, count: columns)) }
            for rr in item.row..<item.maxRow { for cc in item.col..<item.maxCol { occupied[rr][cc] = true } }
        }
        if let pinned, spans.indices.contains(pinned.index) {
            var item = pinned.item
            item.colSpan = min(max(item.colSpan, 1), columns)
            item.col = min(max(item.col, 0), columns - item.colSpan)
            item.row = max(item.row, 0)
            item.rowSpan = max(item.rowSpan, 1)
            items[pinned.index] = item
            occupy(item)
        }
        for (i, span) in spans.enumerated() where i != pinned?.index {
            let w = span.col
            let h = span.row
            var r = 0
            placing: while true {
                for c in 0...(columns - w) where free(r, c, w, h) {
                    let item = Item(col: c, row: r, colSpan: w, rowSpan: h)
                    occupy(item)
                    items[i] = item
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
            items.firstIndex { r >= $0.row && r < $0.maxRow && c >= $0.col && c < $0.maxCol }
        }
        func isFree(_ r: Int, _ c: Int) -> Bool { owner(r, c) == nil }
        var changed = true
        while changed {
            changed = false
            for r in 0..<rows {
                for c in 0..<columns where isFree(r, c) {
                    // Vizinho da esquerda: cresce uma coluna se toda a borda direita dele estiver livre.
                    if c > 0, let i = owner(r, c - 1), items[i].maxCol == c,
                       (items[i].row..<items[i].maxRow).allSatisfy({ isFree($0, c) }) {
                        items[i].colSpan += 1
                        changed = true
                        continue
                    }
                    // Vizinho de cima: cresce uma linha se toda a borda de baixo dele estiver livre.
                    if r > 0, let i = owner(r - 1, c), items[i].maxRow == r,
                       (items[i].col..<items[i].maxCol).allSatisfy({ isFree(r, $0) }) {
                        items[i].rowSpan += 1
                        changed = true
                    }
                }
            }
        }
        return GridLayout(columns: columns, rows: rows, items: items)
    }

    /// Como o grid aparece na tela. Se a última linha só tem painéis de uma linha, todos pedidos
    /// com a mesma largura, mas que ficaram desiguais por causa do esticamento (ex.: 3 colunas e
    /// 2 painéis), divide a linha em partes iguais, como o grid antigo fazia. Para isso cada coluna
    /// vira `m` subcolunas, onde `m` é quantos painéis há na última linha.
    var display: GridLayout {
        let last = rows - 1
        let touching = items.indices.filter { items[$0].maxRow - 1 == last }
        guard touching.count > 1, requestedColSpans.count == items.count,
              touching.allSatisfy({ items[$0].row == last }),
              Set(touching.map { requestedColSpans[$0] }).count == 1,
              Set(touching.map { items[$0].colSpan }).count > 1 else { return self }
        let m = touching.count
        var scaled = items.map { Item(col: $0.col * m, row: $0.row, colSpan: $0.colSpan * m, rowSpan: $0.rowSpan) }
        for (k, i) in touching.sorted(by: { items[$0].col < items[$1].col }).enumerated() {
            scaled[i].col = k * columns
            scaled[i].colSpan = columns
        }
        return GridLayout(columns: columns * m, rows: rows, items: scaled)
    }

    /// Redimensionar: o painel `index` passa a ocupar `target` (em células deste grid, com as
    /// mesmas colunas). Ele é posto primeiro ali; os outros vão, na ordem deles, para a primeira
    /// posição livre (os que estavam no caminho vão para outra coluna ou para uma linha nova).
    /// Devolve a nova ordem dos painéis (índices nos spans recebidos) e os spans nessa ordem:
    /// empacotar isso de novo dá o mesmo grid, então é o que se grava.
    static func resizing(spans: [Span], index: Int, to target: Item, columns: Int) -> (order: [Int], spans: [Span]) {
        var spans = spans
        spans[index] = (col: target.colSpan, row: target.rowSpan)
        let placed = pack(spans.map { (col: min(max($0.col, 1), columns), row: max($0.row, 1)) },
                          columns: columns, pinned: (index, target))
        let order = spans.indices.sorted {
            let a = placed.items[$0], b = placed.items[$1]
            return (a.row, a.col) < (b.row, b.col)
        }
        return (order, order.map { spans[$0] })
    }

    /// Retângulo de cada célula/painel dentro de `size`, com espaçamento e margem.
    func frame(of item: Item, in size: CGSize, spacing: CGFloat, padding: CGFloat) -> CGRect {
        let cell = cellSize(in: size, spacing: spacing, padding: padding)
        return CGRect(
            x: padding + CGFloat(item.col) * (cell.width + spacing),
            y: padding + CGFloat(item.row) * (cell.height + spacing),
            width: CGFloat(item.colSpan) * cell.width + CGFloat(item.colSpan - 1) * spacing,
            height: CGFloat(item.rowSpan) * cell.height + CGFloat(item.rowSpan - 1) * spacing
        )
    }

    func cellSize(in size: CGSize, spacing: CGFloat, padding: CGFloat) -> CGSize {
        CGSize(width: max(0, (size.width - 2 * padding - CGFloat(columns - 1) * spacing) / CGFloat(columns)),
               height: max(0, (size.height - 2 * padding - CGFloat(rows - 1) * spacing) / CGFloat(rows)))
    }

    /// Linha de grade mais próxima de `x` (0...columns), no meio do vão entre células.
    func nearestColumnLine(to x: CGFloat, in size: CGSize, spacing: CGFloat, padding: CGFloat) -> Int {
        let step = cellSize(in: size, spacing: spacing, padding: padding).width + spacing
        guard step > 0 else { return 0 }
        return min(max(Int(((x - padding + spacing / 2) / step).rounded()), 0), columns)
    }

    /// Linha de grade mais próxima de `y` (0...rows).
    func nearestRowLine(to y: CGFloat, in size: CGSize, spacing: CGFloat, padding: CGFloat) -> Int {
        let step = cellSize(in: size, spacing: spacing, padding: padding).height + spacing
        guard step > 0 else { return 0 }
        return min(max(Int(((y - padding + spacing / 2) / step).rounded()), 0), rows)
    }
}

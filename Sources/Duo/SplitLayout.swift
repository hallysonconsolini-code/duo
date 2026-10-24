import CoreGraphics
import Foundation

/// Layout livre dos painéis de um workspace: uma árvore de divisões, como no iTerm e no VS Code.
/// Cada folha é um painel; cada divisão põe os filhos lado a lado (horizontal) ou empilhados
/// (vertical), com a fração do espaço de cada um. Funções puras: não sabe de SwiftUI.
enum SplitNode: Equatable {
    case pane(UUID)
    case split(Split)

    struct Split: Equatable {
        var axis: Axis
        var children: [SplitNode]
        /// Uma por filho, somando 1.
        var fractions: [Double]

        init(axis: Axis, children: [SplitNode], fractions: [Double]? = nil) {
            self.axis = axis
            self.children = children
            self.fractions = fractions ?? Array(repeating: 1 / Double(max(children.count, 1)), count: children.count)
        }
    }

    enum Axis: String, Codable {
        /// Filhos lado a lado (divisória vertical entre eles).
        case horizontal
        /// Filhos empilhados (divisória horizontal entre eles).
        case vertical
    }

    /// Lado de um painel onde outro entra.
    enum Edge: CaseIterable {
        case left, right, top, bottom

        var axis: Axis { self == .left || self == .right ? .horizontal : .vertical }
        /// O painel novo fica antes (à esquerda ou acima) do alvo.
        var isLeading: Bool { self == .left || self == .top }
    }

    /// Divisória entre os filhos `index` e `index + 1` da divisão em `path`.
    struct Divider: Identifiable, Equatable {
        let path: [Int]
        let index: Int
        let axis: Axis
        /// O vão entre os dois filhos (onde a divisória é desenhada e recebe o mouse).
        let rect: CGRect
        /// Retângulo da divisão inteira, para converter arrasto em fração.
        let splitRect: CGRect
        var id: String { path.map(String.init).joined(separator: ".") + "/\(index)" }
    }

    /// Margem em volta dos painéis e vão entre eles, em pontos.
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 6
    /// Menor tamanho de um painel ao arrastar uma divisória.
    static let minPaneSize = CGSize(width: 200, height: 120)

    // MARK: Consultas

    /// Painéis na ordem da árvore (esquerda para direita, cima para baixo).
    var paneIDs: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .split(let s): s.children.flatMap(\.paneIDs)
        }
    }

    func contains(_ id: UUID) -> Bool { paneIDs.contains(id) }

    /// Retângulo de cada painel dentro de `rect`.
    func frames(in rect: CGRect, spacing: CGFloat = SplitNode.spacing) -> [UUID: CGRect] {
        var out: [UUID: CGRect] = [:]
        collectFrames(in: rect, spacing: spacing, into: &out)
        return out
    }

    private func collectFrames(in rect: CGRect, spacing: CGFloat, into out: inout [UUID: CGRect]) {
        switch self {
        case .pane(let id):
            out[id] = rect
        case .split(let s):
            for (child, r) in zip(s.children, s.childRects(in: rect, spacing: spacing)) {
                child.collectFrames(in: r, spacing: spacing, into: &out)
            }
        }
    }

    /// Todas as divisórias, com o vão que cada uma ocupa.
    func dividers(in rect: CGRect, spacing: CGFloat = SplitNode.spacing) -> [Divider] {
        var out: [Divider] = []
        collectDividers(path: [], in: rect, spacing: spacing, into: &out)
        return out
    }

    private func collectDividers(path: [Int], in rect: CGRect, spacing: CGFloat, into out: inout [Divider]) {
        guard case .split(let s) = self else { return }
        let rects = s.childRects(in: rect, spacing: spacing)
        for i in 0..<(rects.count - 1) {
            let a = rects[i], b = rects[i + 1]
            let gap = s.axis == .horizontal
                ? CGRect(x: a.maxX, y: rect.minY, width: b.minX - a.maxX, height: rect.height)
                : CGRect(x: rect.minX, y: a.maxY, width: rect.width, height: b.minY - a.maxY)
            out.append(Divider(path: path, index: i, axis: s.axis, rect: gap, splitRect: rect))
        }
        for (i, child) in s.children.enumerated() {
            child.collectDividers(path: path + [i], in: rects[i], spacing: spacing, into: &out)
        }
    }

    /// Menor tamanho que este nó aceita sem espremer nenhum painel abaixo do mínimo.
    func minSize(pane: CGSize = SplitNode.minPaneSize, spacing: CGFloat = SplitNode.spacing) -> CGSize {
        switch self {
        case .pane:
            return pane
        case .split(let s):
            let sizes = s.children.map { $0.minSize(pane: pane, spacing: spacing) }
            let gaps = spacing * CGFloat(sizes.count - 1)
            switch s.axis {
            case .horizontal:
                return CGSize(width: sizes.reduce(0) { $0 + $1.width } + gaps, height: sizes.map(\.height).max() ?? 0)
            case .vertical:
                return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.reduce(0) { $0 + $1.height } + gaps)
            }
        }
    }

    /// Painel de maior área, quando o layout ocupa `rect`.
    func largestPane(in rect: CGRect) -> UUID? {
        frames(in: rect).max { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
    }

    // MARK: Construção

    /// Grade equilibrada, como o grid antigo: 1, 2, 3 lado a lado; 4 = 2×2; 5 a 9 em 3 colunas;
    /// depois 4. A última linha, se tiver menos painéis, divide a largura entre eles.
    static func grid(_ ids: [UUID]) -> SplitNode? {
        guard !ids.isEmpty else { return nil }
        let columns: Int
        switch ids.count {
        case ...3: columns = ids.count
        case 4: columns = 2
        case 5...9: columns = 3
        default: columns = 4
        }
        let rows = stride(from: 0, to: ids.count, by: columns).map { start -> SplitNode in
            let row = ids[start..<min(start + columns, ids.count)].map(SplitNode.pane)
            return row.count == 1 ? row[0] : .split(Split(axis: .horizontal, children: row))
        }
        return rows.count == 1 ? rows[0] : .split(Split(axis: .vertical, children: rows))
    }

    // MARK: Edição

    /// Põe `id` ao lado de `target`, dividindo o espaço dele ao meio. Se a divisão onde o alvo
    /// está já é no mesmo eixo, o novo vira irmão (sem aninhar).
    func inserting(_ id: UUID, at edge: Edge, of target: UUID) -> SplitNode {
        switch self {
        case .pane(let p):
            guard p == target else { return self }
            let pair: [SplitNode] = edge.isLeading ? [.pane(id), self] : [self, .pane(id)]
            return .split(Split(axis: edge.axis, children: pair))
        case .split(var s):
            for (i, child) in s.children.enumerated() {
                if case .pane(target) = child, s.axis == edge.axis {
                    let half = s.fractions[i] / 2
                    s.fractions[i] = half
                    let at = edge.isLeading ? i : i + 1
                    s.children.insert(.pane(id), at: at)
                    s.fractions.insert(half, at: at)
                    return .split(s)
                }
                if child.contains(target) {
                    s.children[i] = child.inserting(id, at: edge, of: target)
                    return SplitNode.split(s).normalized()
                }
            }
            return self
        }
    }

    /// Tira painéis que não estão em `keep` (e repetidos). O espaço de quem sai vai para o
    /// irmão anterior, ou para o seguinte se era o primeiro. nil = não sobrou nenhum.
    func pruned(keeping keep: Set<UUID>) -> SplitNode? {
        var seen = Set<UUID>()
        return pruned(keeping: keep, seen: &seen)?.normalized()
    }

    private func pruned(keeping keep: Set<UUID>, seen: inout Set<UUID>) -> SplitNode? {
        switch self {
        case .pane(let id):
            guard keep.contains(id), !seen.contains(id) else { return nil }
            seen.insert(id)
            return self
        case .split(let s):
            var children: [SplitNode] = []
            var fractions: [Double] = []
            var carry = 0.0
            for (child, f) in zip(s.children, s.fractions) {
                if let kept = child.pruned(keeping: keep, seen: &seen) {
                    children.append(kept)
                    fractions.append(f + carry)
                    carry = 0
                } else if fractions.isEmpty {
                    carry += f
                } else {
                    fractions[fractions.count - 1] += f
                }
            }
            if children.isEmpty { return nil }
            return .split(Split(axis: s.axis, children: children, fractions: fractions))
        }
    }

    func removing(_ id: UUID) -> SplitNode? {
        pruned(keeping: Set(paneIDs.filter { $0 != id }))
    }

    /// Tira `id` de onde está e o põe em `edge` de `target`.
    func moving(_ id: UUID, to edge: Edge, of target: UUID) -> SplitNode {
        guard id != target, contains(id), contains(target), let rest = removing(id) else { return self }
        return rest.inserting(id, at: edge, of: target)
    }

    /// Todas as divisões com partes iguais.
    func balanced() -> SplitNode {
        guard case .split(var s) = self else { return self }
        s.children = s.children.map { $0.balanced() }
        s.fractions = Array(repeating: 1 / Double(s.children.count), count: s.children.count)
        return .split(s)
    }

    /// Só a divisão em `path` com partes iguais (duplo clique na divisória).
    func balanced(at path: [Int]) -> SplitNode {
        updating(at: path) { s in
            s.fractions = Array(repeating: 1 / Double(s.children.count), count: s.children.count)
        }
    }

    /// Move a divisória `index` da divisão em `path` em `delta` pontos, sem deixar nenhum dos
    /// dois lados abaixo do mínimo. `rect` é o retângulo da divisão. Só os dois vizinhos mudam.
    func resizing(path: [Int], index: Int, by delta: CGFloat, in rect: CGRect,
                  spacing: CGFloat = SplitNode.spacing, minPane: CGSize = SplitNode.minPaneSize) -> SplitNode {
        updating(at: path) { s in
            guard index >= 0, index + 1 < s.children.count else { return }
            let horizontal = s.axis == .horizontal
            let length = horizontal ? rect.width : rect.height
            let available = length - spacing * CGFloat(s.children.count - 1)
            guard available > 0 else { return }
            let total = s.fractions.reduce(0, +)
            let a = CGFloat(s.fractions[index] / total) * available
            let b = CGFloat(s.fractions[index + 1] / total) * available
            func minLength(_ node: SplitNode) -> CGFloat {
                let size = node.minSize(pane: minPane, spacing: spacing)
                return horizontal ? size.width : size.height
            }
            let lower = minLength(s.children[index])
            let upper = a + b - minLength(s.children[index + 1])
            // Sem espaço para os dois mínimos: não mexe.
            guard upper >= lower else { return }
            let newA = min(max(a + delta, lower), upper)
            for i in s.fractions.indices { s.fractions[i] /= total }
            s.fractions[index] = Double(newA / available)
            s.fractions[index + 1] = Double((a + b - newA) / available)
        }
    }

    private func updating(at path: [Int], _ change: (inout Split) -> Void) -> SplitNode {
        guard case .split(var s) = self else { return self }
        if let first = path.first {
            guard s.children.indices.contains(first) else { return self }
            s.children[first] = s.children[first].updating(at: Array(path.dropFirst()), change)
        } else {
            change(&s)
        }
        return .split(s)
    }

    /// Conserta frações inválidas, desfaz divisões de um filho só e junta divisões aninhadas
    /// no mesmo eixo (as frações são multiplicadas, então nada muda de tamanho).
    func normalized() -> SplitNode {
        guard case .split(let s) = self else { return self }
        var fractions = s.fractions
        if fractions.count != s.children.count || fractions.contains(where: { !$0.isFinite || $0 <= 0 }) {
            fractions = Array(repeating: 1, count: s.children.count)
        }
        let total = fractions.reduce(0, +)
        var children: [SplitNode] = []
        var flat: [Double] = []
        for (child, f) in zip(s.children.map { $0.normalized() }, fractions.map { $0 / total }) {
            if case .split(let inner) = child, inner.axis == s.axis {
                children.append(contentsOf: inner.children)
                flat.append(contentsOf: inner.fractions.map { $0 * f })
            } else {
                children.append(child)
                flat.append(f)
            }
        }
        if children.count == 1 { return children[0] }
        return .split(Split(axis: s.axis, children: children, fractions: flat))
    }

    /// Deixa o layout com exatamente os painéis de `ids`: tira os que sumiram e põe os que
    /// faltam dividindo o maior painel no eixo mais longo. Sem layout (workspace salvo por uma
    /// versão antiga), monta a grade equilibrada.
    static func reconciled(_ layout: SplitNode?, with ids: [UUID], bounds: CGSize) -> SplitNode? {
        guard let layout, let kept = layout.pruned(keeping: Set(ids)) else { return grid(ids) }
        var node = kept
        let rect = CGRect(origin: .zero, size: bounds)
        for id in ids where !node.contains(id) {
            guard let target = node.largestPane(in: rect) else { continue }
            node = node.inserting(id, splitting: target, in: rect)
        }
        return node
    }

    /// Divide `target` no eixo mais longo dele (painel novo à direita ou embaixo).
    func inserting(_ id: UUID, splitting target: UUID, in rect: CGRect) -> SplitNode {
        let frame = frames(in: rect)[target] ?? rect
        return inserting(id, at: frame.width >= frame.height ? .right : .bottom, of: target)
    }
}

extension SplitNode.Split {
    /// Retângulo de cada filho. As bordas são arredondadas para pontos inteiros.
    func childRects(in rect: CGRect, spacing: CGFloat) -> [CGRect] {
        let n = children.count
        let horizontal = axis == .horizontal
        let length = horizontal ? rect.width : rect.height
        let available = max(0, length - spacing * CGFloat(n - 1))
        let total = max(fractions.reduce(0, +), .ulpOfOne)
        var rects: [CGRect] = []
        var acc = 0.0
        for i in 0..<n {
            let f = i < fractions.count ? fractions[i] : 0
            let start = (CGFloat(acc / total) * available).rounded() + spacing * CGFloat(i)
            acc += f
            let end = i == n - 1 ? length : (CGFloat(acc / total) * available).rounded() + spacing * CGFloat(i)
            let size = max(0, end - start)
            rects.append(horizontal
                ? CGRect(x: rect.minX + start, y: rect.minY, width: size, height: rect.height)
                : CGRect(x: rect.minX, y: rect.minY + start, width: rect.width, height: size))
        }
        return rects
    }
}

// MARK: Codable

// Formato no workspaces.json: {"pane": "<uuid>"} ou {"axis": "horizontal", "children": [...], "fractions": [...]}.
extension SplitNode: Codable {
    private enum CodingKeys: String, CodingKey { case pane, axis, children, fractions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(UUID.self, forKey: .pane) {
            self = .pane(id)
            return
        }
        let children = try c.decode([SplitNode].self, forKey: .children)
        guard !children.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .children, in: c, debugDescription: "divisão vazia")
        }
        let fractions = try c.decodeIfPresent([Double].self, forKey: .fractions)
        self = SplitNode.split(Split(axis: try c.decode(Axis.self, forKey: .axis), children: children,
                                     fractions: fractions)).normalized()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let id):
            try c.encode(id, forKey: .pane)
        case .split(let s):
            try c.encode(s.axis, forKey: .axis)
            try c.encode(s.children, forKey: .children)
            try c.encode(s.fractions, forKey: .fractions)
        }
    }
}

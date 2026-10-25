import CoreGraphics
import Foundation

/// Zonas de encaixe de um workspace, como no FancyZones e no Rectangle: uma árvore de divisões
/// com frações. Cada folha é uma zona; os painéis de uma zona dividem o espaço dela em grid
/// automático (`GridLayout`). Funções puras: não sabe de SwiftUI.
enum SplitNode: Equatable {
    case zone(UUID)
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

    /// Lado de uma zona onde outra entra.
    enum Edge: CaseIterable {
        case left, right, top, bottom

        var axis: Axis { self == .left || self == .right ? .horizontal : .vertical }
        /// A zona nova fica antes (à esquerda ou acima) da outra.
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

    /// Margem em volta das zonas e vão entre elas (e entre os painéis de uma zona), em pontos.
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 6
    /// Menor tamanho de um painel; uma zona não fica menor que o grid dos painéis dela pede.
    static let minPaneSize = CGSize(width: 200, height: 120)


    // MARK: Consultas

    /// Zonas na ordem da árvore (esquerda para direita, cima para baixo).
    var zoneIDs: [UUID] {
        switch self {
        case .zone(let id): [id]
        case .split(let s): s.children.flatMap(\.zoneIDs)
        }
    }

    func contains(_ id: UUID) -> Bool { zoneIDs.contains(id) }

    /// Retângulo de cada zona dentro de `rect`.
    func frames(in rect: CGRect, spacing: CGFloat = SplitNode.spacing) -> [UUID: CGRect] {
        var out: [UUID: CGRect] = [:]
        collectFrames(in: rect, spacing: spacing, into: &out)
        return out
    }

    private func collectFrames(in rect: CGRect, spacing: CGFloat, into out: inout [UUID: CGRect]) {
        switch self {
        case .zone(let id):
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

    /// Menor tamanho que este nó aceita, com `zoneMin` dizendo o mínimo de cada zona.
    func minSize(spacing: CGFloat = SplitNode.spacing, zoneMin: (UUID) -> CGSize) -> CGSize {
        switch self {
        case .zone(let id):
            return zoneMin(id)
        case .split(let s):
            let sizes = s.children.map { $0.minSize(spacing: spacing, zoneMin: zoneMin) }
            let gaps = spacing * CGFloat(sizes.count - 1)
            switch s.axis {
            case .horizontal:
                return CGSize(width: sizes.reduce(0) { $0 + $1.width } + gaps, height: sizes.map(\.height).max() ?? 0)
            case .vertical:
                return CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.reduce(0) { $0 + $1.height } + gaps)
            }
        }
    }

    /// Mesma forma (eixos e frações), sem olhar os ids das zonas.
    func hasSameShape(as other: SplitNode, tolerance: Double = 0.01) -> Bool {
        switch (self, other) {
        case (.zone, .zone):
            return true
        case (.split(let a), .split(let b)):
            return a.axis == b.axis && a.children.count == b.children.count
                && zip(a.fractions, b.fractions).allSatisfy { abs($0 - $1) <= tolerance }
                && zip(a.children, b.children).allSatisfy { $0.hasSameShape(as: $1, tolerance: tolerance) }
        default:
            return false
        }
    }

    // MARK: Edição

    /// A mesma árvore com ids novos (para aplicar um modelo).
    func withFreshIDs() -> SplitNode {
        switch self {
        case .zone: return .zone(UUID())
        case .split(var s):
            s.children = s.children.map { $0.withFreshIDs() }
            return .split(s)
        }
    }

    /// Põe a zona `id` ao lado de `target`, dividindo o espaço dela ao meio. Se a divisão onde o
    /// alvo está já é no mesmo eixo, a nova vira irmã (sem aninhar).
    func inserting(_ id: UUID, at edge: Edge, of target: UUID) -> SplitNode {
        switch self {
        case .zone(let z):
            guard z == target else { return self }
            let pair: [SplitNode] = edge.isLeading ? [.zone(id), self] : [self, .zone(id)]
            return .split(Split(axis: edge.axis, children: pair))
        case .split(var s):
            for (i, child) in s.children.enumerated() {
                if case .zone(target) = child, s.axis == edge.axis {
                    let half = s.fractions[i] / 2
                    s.fractions[i] = half
                    let at = edge.isLeading ? i : i + 1
                    s.children.insert(.zone(id), at: at)
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

    /// Tira zonas que não estão em `keep` (e repetidas). O espaço de quem sai vai para a irmã
    /// anterior, ou para a seguinte se era a primeira. nil = não sobrou nenhuma.
    func pruned(keeping keep: Set<UUID>) -> SplitNode? {
        var seen = Set<UUID>()
        return pruned(keeping: keep, seen: &seen)?.normalized()
    }

    private func pruned(keeping keep: Set<UUID>, seen: inout Set<UUID>) -> SplitNode? {
        switch self {
        case .zone(let id):
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
                  spacing: CGFloat = SplitNode.spacing, zoneMin: (UUID) -> CGSize) -> SplitNode {
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
                let size = node.minSize(spacing: spacing, zoneMin: zoneMin)
                return horizontal ? size.width : size.height
            }
            // Com pouco espaço, os mínimos são reduzidos na mesma proporção, para a
            // divisória ainda andar um pouco.
            var lower = minLength(s.children[index])
            var other = minLength(s.children[index + 1])
            if lower + other > a + b {
                let scale = (a + b) / (lower + other) * 0.9
                lower *= scale
                other *= scale
            }
            let upper = a + b - other
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

// MARK: Modelos

/// Um modelo de zonas: os prontos do Duo e os que o usuário salvou.
struct ZoneTemplate: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var layout: SplitNode

    static let automaticID = "auto"

    static let builtIn: [ZoneTemplate] = {
        func z() -> SplitNode { .zone(UUID()) }
        func h(_ children: [SplitNode], _ fractions: [Double]? = nil) -> SplitNode {
            .split(.init(axis: .horizontal, children: children, fractions: fractions))
        }
        func v(_ children: [SplitNode], _ fractions: [Double]? = nil) -> SplitNode {
            .split(.init(axis: .vertical, children: children, fractions: fractions))
        }
        return [
            ZoneTemplate(id: automaticID, name: "Automático", layout: z()),
            ZoneTemplate(id: "cols2", name: "2 colunas", layout: h([z(), z()])),
            ZoneTemplate(id: "cols3", name: "3 colunas", layout: h([z(), z(), z()])),
            ZoneTemplate(id: "twoThirds", name: "2/3 + 1/3", layout: h([z(), z()], [2.0 / 3, 1.0 / 3])),
            ZoneTemplate(id: "main", name: "Principal + 2", layout: h([z(), v([z(), z()])], [0.6, 0.4])),
            ZoneTemplate(id: "focus", name: "Foco central", layout: h([z(), z(), z()], [0.25, 0.5, 0.25])),
            ZoneTemplate(id: "grid2x2", name: "2×2", layout: v([h([z(), z()]), h([z(), z()])])),
        ]
    }()

    var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }
}

// MARK: Codable

// Formato no workspaces.json: {"zone": "<uuid>"} ou {"axis": "horizontal", "children": [...], "fractions": [...]}.
extension SplitNode: Codable {
    private enum CodingKeys: String, CodingKey { case zone, axis, children, fractions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(UUID.self, forKey: .zone) {
            self = .zone(id)
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
        case .zone(let id):
            try c.encode(id, forKey: .zone)
        case .split(let s):
            try c.encode(s.axis, forKey: .axis)
            try c.encode(s.children, forKey: .children)
            try c.encode(s.fractions, forKey: .fractions)
        }
    }
}

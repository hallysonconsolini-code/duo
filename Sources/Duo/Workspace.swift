import Foundation

/// Um painel do grid: um Claude Code (terminal) ou o claude.ai de uma conta.
struct PaneSpec: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case claude
        case web
    }

    var id = UUID()
    var kind: Kind
    /// Nome curto e estável dentro do workspace ("p1", "p2"...), usado pelas ferramentas MCP.
    var name: String
    var accountID: UUID
    var directory: String
    /// Sessão do Claude Code, para retomar a conversa quando o app reabrir.
    var claudeSessionID: String?
    var claudeTranscriptPath: String?
    /// Papel na equipe (id em RoleStore). Gravado como texto, igual ao antigo enum TeamRole.
    var role: RoleID?
    /// Alias passado em `--model` (opus, sonnet...). nil = padrão da conta.
    var model: String?
    /// Valor passado em `--effort`. nil = padrão da conta.
    var effort: String?
    /// Instruções do papel, passadas em `--append-system-prompt`.
    var systemPrompt: String?
    /// Branch do worktree do dev, quando tem cópia isolada.
    var branch: String?
    /// Painel aberto pelo ⌘T esperando a escolha de papel; o claude ainda não iniciou.
    /// Não sobrevive a reabrir o app (é descartado ao carregar).
    var awaitingRole: Bool?
    /// Zona do workspace onde o painel fica. nil, ou uma zona que não existe mais (arquivos
    /// de versões antigas), é resolvido pela regra do painel novo ao carregar.
    var zone: UUID?

    var isAwaitingRole: Bool { awaitingRole == true }

    /// Só dá para retomar uma sessão que já tem conversa gravada em disco.
    var resumableSessionID: String? {
        guard let id = claudeSessionID, let path = claudeTranscriptPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return id
    }
}

/// Um projeto: uma pasta e os painéis que trabalham nela, arrumados em zonas.
///
/// Arquivos de versões anteriores abrem no modelo Automático (uma zona só): o `layout` da 0.3.6
/// (árvore de painéis) e o `colSpan`/`rowSpan` da 0.3.7 são ignorados.
struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var directory: String
    var panes: [PaneSpec] = []
    /// Zonas de encaixe. nil em arquivos antigos e em workspace recém-criado: uma zona só,
    /// com o id do próprio workspace (estável, então os painéis não perdem a zona).
    var zones: SplitNode?

    var zoneLayout: SplitNode { zones ?? .zone(id) }

    /// Painéis da zona, na ordem do workspace (a ordem do grid dentro dela).
    func panes(in zone: UUID) -> [PaneSpec] { panes.filter { $0.zone == zone } }

    /// Garante zonas e uma zona válida para cada painel. Nunca tira zonas: fechar um painel
    /// deixa a zona dele como estava (vazia, se era o único).
    mutating func syncZones() {
        if zones == nil { zones = .zone(id) }
        let valid = Set(zoneLayout.zoneIDs)
        for i in panes.indices where panes[i].zone.map({ !valid.contains($0) }) ?? true {
            panes[i].zone = nil
        }
        for i in panes.indices where panes[i].zone == nil {
            panes[i].zone = zoneForNewPane()
        }
    }

    /// Regra do painel novo: a zona com menos painéis (vazias primeiro); no empate, a última
    /// na ordem da árvore.
    func zoneForNewPane() -> UUID {
        let ids = zoneLayout.zoneIDs
        var counts: [UUID: Int] = [:]
        for pane in panes { if let z = pane.zone { counts[z, default: 0] += 1 } }
        var best = ids[0]
        for id in ids where counts[id, default: 0] <= counts[best, default: 0] { best = id }
        return best
    }

    /// Troca as zonas pelas de um modelo (com ids novos). Painel 1 na zona 1, painel 2 na
    /// zona 2…; o excesso vai pela regra do painel novo.
    mutating func apply(_ template: SplitNode) {
        let layout = template.withFreshIDs()
        let ids = layout.zoneIDs
        zones = layout
        for i in panes.indices { panes[i].zone = i < ids.count ? ids[i] : nil }
        syncZones()
    }

    /// Põe o painel na zona `zone`, depois dos que já estão lá.
    mutating func move(_ paneID: UUID, toZone zone: UUID) {
        guard zoneLayout.contains(zone), let i = panes.firstIndex(where: { $0.id == paneID }),
              panes[i].zone != zone else { return }
        var pane = panes.remove(at: i)
        pane.zone = zone
        let after = panes.lastIndex { $0.zone == zone }.map { $0 + 1 } ?? panes.count
        panes.insert(pane, at: after)
    }

    /// Cria uma zona no lado `edge` da zona `target` (dividindo-a) e põe o painel nela.
    mutating func split(_ target: UUID, at edge: SplitNode.Edge, movingPane paneID: UUID) {
        guard zoneLayout.contains(target) else { return }
        let new = UUID()
        zones = zoneLayout.inserting(new, at: edge, of: target)
        move(paneID, toZone: new)
    }

    /// Tira as zonas sem painel (o espaço vai para a vizinha). Sobra pelo menos uma.
    mutating func removeEmptyZones() {
        let used = Set(panes.compactMap(\.zone))
        zones = zoneLayout.pruned(keeping: used) ?? .zone(zoneLayout.zoneIDs[0])
        syncZones()
    }

    func nextPaneName() -> String {
        let used = Set(panes.map(\.name))
        var n = 1
        while used.contains("p\(n)") { n += 1 }
        return "p\(n)"
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [Workspace] {
        didSet { save() }
    }

    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedWorkspace") }
    }

    init() {
        if let data = try? Data(contentsOf: Paths.workspacesFile),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            // Painéis que ficaram em "escolher papel" não têm processo nem conversa: descarta.
            workspaces = decoded.map { ws in
                var ws = ws
                ws.panes.removeAll { $0.isAwaitingRole }
                ws.syncZones()
                return ws
            }
        } else {
            workspaces = []
        }
        let saved = UserDefaults.standard.string(forKey: "selectedWorkspace").flatMap(UUID.init)
        selectedID = workspaces.first { $0.id == saved }?.id ?? workspaces.first?.id
    }

    var selected: Workspace? {
        workspaces.first { $0.id == selectedID }
    }

    func workspace(containing paneID: UUID) -> Workspace? {
        workspaces.first { $0.panes.contains { $0.id == paneID } }
    }

    func pane(_ id: UUID) -> PaneSpec? {
        for ws in workspaces {
            if let pane = ws.panes.first(where: { $0.id == id }) { return pane }
        }
        return nil
    }

    func update(_ workspaceID: UUID, _ change: (inout Workspace) -> Void) {
        guard let i = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        var ws = workspaces[i]
        change(&ws)
        ws.syncZones()
        if ws != workspaces[i] { workspaces[i] = ws }
    }

    func updatePane(_ paneID: UUID, _ change: (inout PaneSpec) -> Void) {
        guard let ws = workspace(containing: paneID) else { return }
        update(ws.id) { ws in
            if let j = ws.panes.firstIndex(where: { $0.id == paneID }) { change(&ws.panes[j]) }
        }
    }

    private static let ioQueue = DispatchQueue(label: "duo.workspaces.save")
    private var savePending = false

    /// Agrupa as gravações e as tira da main thread: os hooks de sessão mexem nos
    /// painéis várias vezes por segundo e cada escrita travava a interface.
    private func save() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.savePending = false
            let snapshot = self.workspaces
            Self.ioQueue.async { Self.write(snapshot) }
        }
    }

    /// Grava agora, sem esperar o agrupamento (usada ao encerrar o app).
    func flushSave() {
        savePending = false
        let snapshot = workspaces
        Self.ioQueue.sync { Self.write(snapshot) }
    }

    private nonisolated static func write(_ list: [Workspace]) {
        do {
            try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(list).write(to: Paths.workspacesFile, options: .atomic)
        } catch {
            NSLog("Duo: falha ao salvar workspaces: \(error)")
        }
    }
}

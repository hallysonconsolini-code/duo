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
    var isAwaitingRole: Bool { awaitingRole == true }

    /// Só dá para retomar uma sessão que já tem conversa gravada em disco.
    var resumableSessionID: String? {
        guard let id = claudeSessionID, let path = claudeTranscriptPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return id
    }
}

/// Um projeto: uma pasta e os painéis que trabalham nela.
struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var directory: String
    var panes: [PaneSpec] = []
    /// Como os painéis dividem a tela. Workspaces salvos por versões antigas não têm:
    /// ganham uma grade equilibrada ao carregar. Sempre com os mesmos painéis de `panes`.
    var layout: SplitNode?

    /// Põe o layout de acordo com `panes` (tira quem saiu, encaixa quem chegou).
    mutating func syncLayout(bounds: CGSize) {
        layout = SplitNode.reconciled(layout, with: panes.map(\.id), bounds: bounds)
    }

    /// Encaixa o painel `id` (já em `panes`) dividindo `target`, ou o maior painel se o alvo não
    /// estiver aqui. Sem `edge`, divide no eixo mais longo do alvo.
    mutating func insertInLayout(_ id: UUID, splitting target: UUID?, edge: SplitNode.Edge? = nil, bounds: CGSize) {
        guard var node = layout?.pruned(keeping: Set(panes.map(\.id).filter { $0 != id })) else {
            syncLayout(bounds: bounds)
            return
        }
        let rect = CGRect(origin: .zero, size: bounds)
        guard let target = target.flatMap({ node.contains($0) ? $0 : nil }) ?? node.largestPane(in: rect) else { return }
        node = edge.map { node.inserting(id, at: $0, of: target) } ?? node.inserting(id, splitting: target, in: rect)
        layout = node
        syncLayout(bounds: bounds)
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

    /// Tamanho da área dos painéis, para decidir o eixo de cada divisão nova. A view atualiza.
    var layoutBounds = WorkspaceStore.defaultLayoutBounds
    static let defaultLayoutBounds = CGSize(width: 1250, height: 800)

    init() {
        if let data = try? Data(contentsOf: Paths.workspacesFile),
           let decoded = try? JSONDecoder().decode([Workspace].self, from: data) {
            // Painéis que ficaram em "escolher papel" não têm processo nem conversa: descarta.
            workspaces = decoded.map { ws in
                var ws = ws
                ws.panes.removeAll { $0.isAwaitingRole }
                ws.syncLayout(bounds: Self.defaultLayoutBounds)
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
        ws.syncLayout(bounds: layoutBounds)
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

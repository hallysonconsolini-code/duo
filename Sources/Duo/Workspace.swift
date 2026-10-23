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
    /// Quantas colunas e linhas do grid o painel ocupa (1 ou 2). Arquivos antigos não têm: 1.
    var colSpan = 1
    var rowSpan = 1

    var isAwaitingRole: Bool { awaitingRole == true }

    var size: PaneSize {
        get { PaneSize(colSpan: colSpan, rowSpan: rowSpan) }
        set { colSpan = newValue.colSpan; rowSpan = newValue.rowSpan }
    }

    /// Só dá para retomar uma sessão que já tem conversa gravada em disco.
    var resumableSessionID: String? {
        guard let id = claudeSessionID, let path = claudeTranscriptPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return id
    }
}

extension PaneSpec {
    // Decodificação escrita à mão só para que colSpan e rowSpan tenham padrão 1
    // quando faltam (workspaces.json de versões anteriores). A codificação continua sintetizada.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        accountID = try c.decode(UUID.self, forKey: .accountID)
        directory = try c.decode(String.self, forKey: .directory)
        claudeSessionID = try c.decodeIfPresent(String.self, forKey: .claudeSessionID)
        claudeTranscriptPath = try c.decodeIfPresent(String.self, forKey: .claudeTranscriptPath)
        role = try c.decodeIfPresent(RoleID.self, forKey: .role)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        awaitingRole = try c.decodeIfPresent(Bool.self, forKey: .awaitingRole)
        colSpan = PaneSize.clamp(try c.decodeIfPresent(Int.self, forKey: .colSpan) ?? 1)
        rowSpan = PaneSize.clamp(try c.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 1)
    }
}

/// Tamanhos prontos de um painel no grid.
enum PaneSize: CaseIterable, Hashable {
    case normal, wide, tall, large

    init(colSpan: Int, rowSpan: Int) {
        switch (colSpan >= 2, rowSpan >= 2) {
        case (false, false): self = .normal
        case (true, false): self = .wide
        case (false, true): self = .tall
        case (true, true): self = .large
        }
    }

    var colSpan: Int { self == .wide || self == .large ? 2 : 1 }
    var rowSpan: Int { self == .tall || self == .large ? 2 : 1 }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .wide: "Largo"
        case .tall: "Alto"
        case .large: "Grande"
        }
    }

    var label: String { "\(title) \(colSpan)×\(rowSpan)" }

    /// Atalho de aumentar: 1×1 → 2×1 → 2×2 (o alto vai para o grande).
    var bigger: PaneSize {
        switch self {
        case .normal: .wide
        case .wide, .tall, .large: .large
        }
    }

    /// Atalho de diminuir: 2×2 → 2×1 → 1×1 (o alto vai para o normal).
    var smaller: PaneSize {
        switch self {
        case .large: .wide
        case .wide, .tall, .normal: .normal
        }
    }

    static func clamp(_ span: Int) -> Int { min(max(span, 1), 2) }
}

/// Um projeto: uma pasta e o grid de painéis que trabalham nela.
struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var directory: String
    var panes: [PaneSpec] = []

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

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

    /// Só dá para retomar uma sessão que já tem conversa gravada em disco.
    var resumableSessionID: String? {
        guard let id = claudeSessionID, let path = claudeTranscriptPath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return id
    }
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
            workspaces = decoded
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

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(workspaces).write(to: Paths.workspacesFile, options: .atomic)
        } catch {
            NSLog("Duo: falha ao salvar workspaces: \(error)")
        }
    }
}

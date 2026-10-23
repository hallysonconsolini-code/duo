import AppKit

/// Estado vivo do app: os processos de cada painel, o claude.ai de cada conta,
/// o painel em foco e a ponte que os Claude Code usam para conversar entre si.
@MainActor
final class Cockpit: ObservableObject {
    let accounts: AccountStore
    let workspaces: WorkspaceStore
    let roles: RoleStore

    @Published var focusedPane: UUID? {
        didSet { if focusedPane != oldValue { focusViewOfFocusedPane() } }
    }
    @Published var zoomed = false
    /// Pasta aguardando a escolha de equipe (abre a sheet de equipe).
    @Published var teamSetup: TeamSetupRequest?
    @Published private(set) var isReady = false

    private(set) var terminals: [UUID: TerminalSession] = [:]
    private var webs: [UUID: WebPane] = [:]
    private var waiters: [UUID: [Waiter]] = [:]
    private var bridge: Bridge!
    private var mouseMonitor: Any?

    init(accounts: AccountStore, workspaces: WorkspaceStore, roles: RoleStore) {
        self.accounts = accounts
        self.workspaces = workspaces
        self.roles = roles
        bridge = Bridge { [weak self] request in
            await self?.handle(request) ?? .empty(404)
        }
        do {
            try bridge.start { [weak self] in self?.bridgeReady() }
        } catch {
            NSLog("Duo: ponte não iniciou: \(error)")
        }
        // Clicar dentro de um painel o coloca em foco.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.focusPane(at: event)
            return event
        }
    }

    private func bridgeReady() {
        isReady = true
        for ws in workspaces.workspaces {
            for pane in ws.panes where pane.kind == .claude {
                launch(pane, prompt: nil)
            }
        }
        if focusedPane == nil { focusedPane = workspaces.selected?.panes.first?.id }
    }

    // MARK: Painéis

    func terminal(_ paneID: UUID) -> TerminalSession? { terminals[paneID] }

    func web(for accountID: UUID) -> WebPane {
        if let web = webs[accountID] { return web }
        let account = accounts.account(accountID)
        let web = WebPane(storeID: account?.webStoreID ?? accountID)
        webs[accountID] = web
        return web
    }

    private func launch(_ pane: PaneSpec, prompt: String?) {
        guard let account = accounts.account(pane.accountID) else { return }
        let term = TerminalSession(pane: pane, account: account, bridge: bridge.info, initialPrompt: prompt)
        // Sem reenviar o objectWillChange do terminal para o Cockpit: isso recriava a
        // janela inteira a cada mudança de título/status de qualquer painel. As views
        // que dependem de um terminal observam esse terminal direto.
        terminals[pane.id] = term
    }

    /// Abre a sheet de nova equipe; a pasta do projeto é escolhida dentro dela.
    func openWorkspace() {
        teamSetup = TeamSetupRequest(directory: nil, workspaceID: nil)
    }

    /// Seletor de pasta do projeto, como sheet sobre a janela da frente (que pode ser
    /// a própria sheet de equipe).
    func chooseFolder(_ done: @escaping @MainActor (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Escolher"
        panel.message = "Pasta do projeto"
        // Em sheet, não modal: runModal() parava o run loop principal e congelava
        // todos os painéis enquanto o seletor de pasta estava aberto.
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            done(url.path)
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in MainActor.assumeIsolated { finish(response) } }
        } else {
            panel.begin { response in MainActor.assumeIsolated { finish(response) } }
        }
    }

    /// Workspace já aberto nesta pasta, se houver.
    func workspace(at directory: String) -> Workspace? {
        workspaces.workspaces.first { $0.directory == directory }
    }

    /// Abre a escolha de equipe para o workspace atual (adiciona painéis a ele).
    func setUpTeamInSelectedWorkspace() {
        guard let ws = workspaces.selected else { return }
        teamSetup = TeamSetupRequest(directory: ws.directory, workspaceID: ws.id)
    }

    /// Conclui a sheet de equipe. `slots` vazio = um painel só, sem papel.
    func finishTeamSetup(_ request: TeamSetupRequest, directory: String, slots: [TeamSlot], singleAccount: UUID?) {
        teamSetup = nil
        let wsID: UUID
        if let existing = request.workspaceID, workspaces.workspaces.contains(where: { $0.id == existing }) {
            wsID = existing
        } else if let existing = workspace(at: directory) {
            wsID = existing.id
        } else {
            let url = URL(fileURLWithPath: directory)
            let ws = Workspace(name: url.lastPathComponent, directory: directory)
            workspaces.workspaces.append(ws)
            wsID = ws.id
        }
        selectWorkspace(wsID)
        if slots.isEmpty {
            addPane(kind: .claude, accountID: singleAccount ?? accounts.accounts.first?.id, in: wsID)
        } else {
            createTeam(slots, in: wsID)
        }
    }

    /// Cria um painel por membro, cada um com papel, modelo, esforço e instruções.
    /// Com 2 ou mais que editam código, cada um ganha um git worktree próprio.
    func createTeam(_ slots: [TeamSlot], in wsID: UUID) {
        guard let ws = workspaces.workspaces.first(where: { $0.id == wsID }) else { return }
        let devCount = slots.filter { roles.role($0.role).editsCode }.count
        var draft = ws
        var specs: [PaneSpec] = []
        for slot in slots {
            guard let accountID = slot.accountID ?? accounts.accounts.first?.id else { continue }
            let name = draft.nextPaneName()
            var pane = PaneSpec(kind: .claude, name: name, accountID: accountID, directory: ws.directory)
            assign(slot, to: &pane, isolate: devCount >= 2, projectDir: ws.directory)
            draft.panes.append(pane)
            specs.append(pane)
        }
        // A equipe inteira deste workspace (inclui membros que já estavam lá).
        let team = Self.team(of: draft)
        for i in specs.indices {
            specs[i].systemPrompt = TeamPrompt.build(for: specs[i], team: team, projectDir: ws.directory, roles: roles)
        }
        workspaces.update(wsID) { $0.panes.append(contentsOf: specs) }
        for pane in specs { launch(pane, prompt: nil) }
        zoomed = false
        focusedPane = (specs.first { $0.role == .manager } ?? specs.first)?.id
    }

    /// Dá papel, modelo e esforço a um painel. Quem edita código, com `isolate`, ganha um git worktree próprio.
    private func assign(_ slot: TeamSlot, to pane: inout PaneSpec, isolate: Bool, projectDir: String) {
        pane.role = slot.role
        pane.model = slot.model.rawValue
        pane.effort = slot.effort.rawValue
        if roles.role(slot.role).editsCode, isolate, let tree = Worktrees.create(for: projectDir, paneName: pane.name) {
            pane.directory = tree.directory
            pane.branch = tree.branch
        }
    }

    /// Membros com papel de um workspace (para o system prompt).
    private static func team(of ws: Workspace) -> [PaneSpec] {
        ws.panes.filter { $0.kind == .claude && $0.role != nil }
    }

    /// Conclui o "escolher papel" de um painel aberto pelo ⌘T e inicia o claude.
    /// `role` nil = Claude Code comum, sem papel.
    func chooseRole(_ roleID: RoleID?, for paneID: UUID) {
        guard let ws = workspaces.workspace(containing: paneID),
              var pane = ws.panes.first(where: { $0.id == paneID }), pane.isAwaitingRole else { return }
        pane.awaitingRole = nil
        if let roleID {
            let role = roles.role(roleID)
            // Com este, 2+ que editam código no workspace: o novo ganha worktree. Os que já existem não mudam.
            let devs = ws.panes.filter { $0.id != paneID && $0.role.map { roles.role($0).editsCode } == true }.count
                + (role.editsCode ? 1 : 0)
            assign(TeamSlot(role: role), to: &pane, isolate: devs >= 2, projectDir: ws.directory)
            var draft = ws
            if let i = draft.panes.firstIndex(where: { $0.id == paneID }) { draft.panes[i] = pane }
            pane.systemPrompt = TeamPrompt.build(for: pane, team: Self.team(of: draft), projectDir: ws.directory, roles: roles)
        }
        let updated = pane
        workspaces.updatePane(paneID) { $0 = updated }
        launch(updated, prompt: nil)
        if focusedPane == paneID { focusViewOfFocusedPane() }
    }

    func closeWorkspace(_ id: UUID) {
        guard let ws = workspaces.workspaces.first(where: { $0.id == id }) else { return }
        let running = ws.panes.filter { $0.kind == .claude && !$0.isAwaitingRole && terminals[$0.id]?.status != .exited }
        if !running.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Fechar o workspace “\(ws.name)”?"
            alert.informativeText = "\(running.count) Claude Code será(ão) encerrado(s)."
            alert.addButton(withTitle: "Fechar")
            alert.addButton(withTitle: "Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        for pane in ws.panes { terminals.removeValue(forKey: pane.id)?.terminate() }
        workspaces.workspaces.removeAll { $0.id == id }
        if workspaces.selectedID == id { workspaces.selectedID = workspaces.workspaces.first?.id }
    }

    /// Tela de nova equipe aberta sem workspace de destino: o workspace selecionado não é o alvo.
    var isCreatingWorkspace: Bool { teamSetup.map { $0.workspaceID == nil } ?? false }

    func selectWorkspace(_ id: UUID) {
        workspaces.selectedID = id
        teamSetup = nil
        zoomed = false
        focusedPane = workspaces.selected?.panes.first?.id
    }

    /// Conta do painel em foco, ou a primeira.
    var focusedAccountID: UUID? {
        if let id = focusedPane, let pane = workspaces.pane(id) { return pane.accountID }
        return accounts.accounts.first?.id
    }

    /// A conta seguinte à do painel em foco (atalho "outra conta").
    var otherAccountID: UUID? {
        let list = accounts.accounts
        guard let current = focusedAccountID, let i = list.firstIndex(where: { $0.id == current }) else {
            return list.first?.id
        }
        return list[(i + 1) % list.count].id
    }

    @discardableResult
    func addPane(kind: PaneSpec.Kind, accountID: UUID?, in workspaceID: UUID? = nil,
                 prompt: String? = nil, focus: Bool = true, askRole: Bool = false) -> PaneSpec? {
        guard let accountID = accountID ?? accounts.accounts.first?.id,
              let wsID = workspaceID ?? workspaces.selectedID,
              let ws = workspaces.workspaces.first(where: { $0.id == wsID }) else { return nil }

        // O claude.ai de uma conta é uma view só: se já está aberto, apenas vai até ele.
        if kind == .web, let existing = workspaces.workspaces
            .flatMap({ w in w.panes.map { (w, $0) } })
            .first(where: { $0.1.kind == .web && $0.1.accountID == accountID }) {
            selectWorkspace(existing.0.id)
            focusedPane = existing.1.id
            return existing.1
        }

        var pane = PaneSpec(kind: kind, name: ws.nextPaneName(), accountID: accountID, directory: ws.directory)
        // Com askRole, o painel aparece em "escolher papel" e o claude só inicia em chooseRole.
        if kind == .claude, askRole { pane.awaitingRole = true }
        workspaces.update(wsID) { $0.panes.append(pane) }
        if kind == .claude, !pane.isAwaitingRole { launch(pane, prompt: prompt) }
        if focus {
            if workspaces.selectedID != wsID { workspaces.selectedID = wsID }
            zoomed = false
            focusedPane = pane.id
        }
        return pane
    }

    func closePane(_ id: UUID, confirm: Bool = true) {
        guard let pane = workspaces.pane(id), let ws = workspaces.workspace(containing: id) else { return }
        if confirm, pane.kind == .claude, let term = terminals[id], term.status != .exited {
            let alert = NSAlert()
            alert.messageText = "Fechar \(pane.name)?"
            alert.informativeText = "O Claude Code deste painel será encerrado."
            alert.addButton(withTitle: "Fechar")
            alert.addButton(withTitle: "Cancelar")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        terminals.removeValue(forKey: id)?.terminate()
        let index = ws.panes.firstIndex { $0.id == id } ?? 0
        workspaces.update(ws.id) { $0.panes.removeAll { $0.id == id } }
        if focusedPane == id {
            let remaining = workspaces.workspaces.first { $0.id == ws.id }?.panes ?? []
            focusedPane = remaining.isEmpty ? nil : remaining[max(0, min(index, remaining.count) - 1)].id
            if remaining.isEmpty { zoomed = false }
        }
    }

    func closeFocusedPane() {
        if let id = focusedPane { closePane(id) }
    }

    func focusPane(number: Int) {
        guard let panes = workspaces.selected?.panes, number >= 1, number <= panes.count else { return }
        focusedPane = panes[number - 1].id
    }

    func cycleWorkspace(_ delta: Int) {
        let list = workspaces.workspaces
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == workspaces.selectedID } ?? 0
        selectWorkspace(list[(i + delta + list.count) % list.count].id)
    }

    func view(for pane: PaneSpec) -> NSView? {
        switch pane.kind {
        case .claude: terminals[pane.id]?.view
        case .web: web(for: pane.accountID).webView
        }
    }

    private func focusViewOfFocusedPane() {
        guard let id = focusedPane, let pane = workspaces.pane(id), let view = view(for: pane) else { return }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    private func focusPane(at event: NSEvent) {
        guard let panes = workspaces.selected?.panes else { return }
        for pane in panes {
            guard let view = view(for: pane), view.window === event.window, !view.isHiddenOrHasHiddenAncestor else { continue }
            let point = view.convert(event.locationInWindow, from: nil)
            if view.bounds.contains(point) {
                if focusedPane != pane.id { focusedPane = pane.id }
                // Garante que o teclado vá para o terminal clicado.
                if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
                return
            }
        }
    }

    /// Manda a última resposta de um painel como mensagem para outro.
    func forwardLastReply(from sourceID: UUID, to targetID: UUID) {
        guard let source = workspaces.pane(sourceID), let term = terminals[sourceID],
              let target = terminals[targetID] else { return }
        let reply = term.lastReply() ?? term.screenText(lines: 60)
        target.inject("[resposta de \(source.name)]\n\(reply)")
        focusedPane = targetID
    }

    var anyRunning: Bool { terminals.values.contains { $0.status != .exited } }

    func terminateAll() {
        terminals.values.forEach { $0.terminate() }
    }

    func discardAccount(_ id: UUID) {
        for ws in workspaces.workspaces {
            for pane in ws.panes where pane.accountID == id { closePane(pane.id, confirm: false) }
        }
        webs.removeValue(forKey: id)
    }

    // MARK: Ponte (hooks e MCP)

    private func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard let paneID = request.header("x-duo-pane").flatMap(UUID.init) else { return .empty(400) }
        if request.path.hasPrefix("/hook/") {
            handleHook(String(request.path.dropFirst("/hook/".count)), pane: paneID, body: request.body)
            return .empty(200)
        }
        if request.path.hasPrefix("/mcp") {
            return await handleMCP(request, caller: paneID)
        }
        return .empty(404)
    }

    private func handleHook(_ event: String, pane: UUID, body: Data) {
        guard let term = terminals[pane] else { return }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let sid = json["session_id"] as? String
        let path = json["transcript_path"] as? String
        if sid != nil || path != nil {
            if let sid { term.sessionID = sid }
            if let path { term.transcriptPath = path }
            workspaces.updatePane(pane) {
                $0.claudeSessionID = term.sessionID
                $0.claudeTranscriptPath = term.transcriptPath
            }
        }

        switch event {
        case "SessionStart":
            term.status = .idle
        case "UserPromptSubmit", "PreToolUse":
            term.status = .working
        case "Stop":
            term.status = .idle
            term.refreshActualModel()
            term.injectedSinceStop = false
            resumeWaiters(pane)
        case "Notification":
            // O aviso de "esperando sua mensagem" chega com o painel já parado; só permissões contam.
            let message = (json["message"] as? String ?? "").lowercased()
            if !message.contains("waiting for your input") { term.status = .attention }
        case "SessionEnd":
            term.status = .exited
            resumeWaiters(pane)
        default:
            break
        }
    }

    private final class Waiter {
        var continuation: CheckedContinuation<Bool, Never>?
        func resume(_ value: Bool) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private func resumeWaiters(_ pane: UUID) {
        waiters.removeValue(forKey: pane)?.forEach { $0.resume(true) }
    }

    /// Espera o painel terminar a vez dele. Retorna false se der timeout.
    private func waitForStop(_ pane: UUID, timeout: TimeInterval) async -> Bool {
        let waiter = Waiter()
        return await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            waiters[pane, default: []].append(waiter)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.waiters[pane]?.removeAll { $0 === waiter }
                waiter.resume(false)
            }
        }
    }

    private func handleMCP(_ request: HTTPRequest, caller: UUID) async -> HTTPResponse {
        switch request.method {
        case "GET": return .empty(405)
        case "DELETE": return .empty(200)
        default: break
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: request.body) else { return .empty(400) }
        let messages = (parsed as? [[String: Any]]) ?? [(parsed as? [String: Any]) ?? [:]]
        var responses: [[String: Any]] = []
        for message in messages {
            if let response = await handleRPC(message, caller: caller) { responses.append(response) }
        }
        if responses.isEmpty { return .empty(202) }
        return parsed is [Any] ? .json(responses) : .json(responses[0])
    }

    private func handleRPC(_ message: [String: Any], caller: UUID) async -> [String: Any]? {
        guard let id = message["id"] else { return nil }  // notificação
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        func reply(_ result: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": result] }

        switch method {
        case "initialize":
            return reply([
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "duo", "version": Updater.currentVersion],
                "instructions": MCPTools.instructions,
            ])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": MCPTools.definitions])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = await callTool(name, args, caller: caller)
            return reply(["content": [["type": "text", "text": text]], "isError": isError])
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "método desconhecido: \(method)"]]
        }
    }

    private enum Target {
        case ok(PaneSpec, TerminalSession)
        case fail(String)
    }

    private func callTool(_ name: String, _ args: [String: Any], caller: UUID) async -> (String, Bool) {
        guard let ws = workspaces.workspace(containing: caller), let me = ws.panes.first(where: { $0.id == caller }) else {
            return ("Este painel não pertence a nenhum workspace.", true)
        }
        func target() -> Target {
            let wanted = (args["pane"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard let pane = ws.panes.first(where: { $0.name.lowercased() == wanted }) else {
                return .fail("Painel “\(wanted)” não existe. Use list_panes.")
            }
            guard pane.id != caller else { return .fail("Esse é o seu próprio painel.") }
            if pane.isAwaitingRole { return .fail("\(pane.name) ainda está escolhendo papel.") }
            guard pane.kind == .claude, let term = terminals[pane.id] else {
                return .fail("\(pane.name) não é um Claude Code.")
            }
            return .ok(pane, term)
        }

        switch name {
        case "list_panes":
            let lines = ws.panes.map { pane -> String in
                let account = accounts.account(pane.accountID)?.name ?? "?"
                let status = pane.kind == .web ? "claude.ai"
                    : pane.isAwaitingRole ? "escolhendo papel" : (terminals[pane.id]?.status.label ?? "?")
                let me = pane.id == caller ? "  ← você" : ""
                var who = pane.name
                if let role = pane.role { who += " (\(roles.role(role).short))" }
                if let model = pane.model { who += " · \(model)" }
                return "\(who) · \(account) · \(status)\(me)"
            }
            return ("Workspace \(ws.name) (\(ws.directory))\n" + lines.joined(separator: "\n"), false)

        case "send_to_pane":
            switch target() {
            case .fail(let message): return (message, true)
            case .ok(let pane, let term):
                guard let text = args["message"] as? String, !text.isEmpty else { return ("Falta message.", true) }
                guard term.status != .exited else { return ("\(pane.name) está encerrado.", true) }
                term.inject("[mensagem de \(me.name)]\n\(text)")
                return ("Enviado para \(pane.name). Use wait_for_pane para esperar a resposta.", false)
            }

        case "read_pane":
            switch target() {
            case .fail(let message): return (message, true)
            case .ok(let pane, let term):
                let lines = args["lines"] as? Int ?? 80
                if (args["source"] as? String) == "screen" {
                    return ("Tela de \(pane.name) (\(term.status.label)):\n\(term.screenText(lines: lines))", false)
                }
                let reply = term.lastReply() ?? "(sem resposta ainda)"
                return ("Última resposta de \(pane.name) (\(term.status.label)):\n\(reply)", false)
            }

        case "wait_for_pane":
            switch target() {
            case .fail(let message): return (message, true)
            case .ok(let pane, let term):
                let timeout = TimeInterval(args["timeout_seconds"] as? Int ?? 900)
                let previous = term.lastReply()
                var waited = false
                if term.status == .working || term.status == .starting || term.injectedSinceStop {
                    let finished = await waitForStop(pane.id, timeout: timeout)
                    if !finished { return ("\(pane.name) ainda está \(term.status.label) após \(Int(timeout))s.", true) }
                    waited = true
                }
                if term.status == .attention {
                    return ("\(pane.name) está esperando uma permissão do usuário.", false)
                }
                // O hook Stop pode chegar antes de a resposta ser gravada no transcript.
                var reply = term.lastReply()
                if waited {
                    for _ in 0..<15 where reply == nil || reply == previous {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        reply = term.lastReply()
                    }
                }
                let text = reply ?? term.screenText(lines: 60)
                return ("\(pane.name) terminou. Resposta:\n\(text)", false)
            }

        case "spawn_pane":
            var accountID = me.accountID
            if let wanted = (args["account"] as? String)?.lowercased(), !wanted.isEmpty {
                if let match = accounts.accounts.first(where: { $0.name.lowercased() == wanted }) {
                    accountID = match.id
                } else if wanted == "outra" || wanted == "other",
                          let i = accounts.accounts.firstIndex(where: { $0.id == me.accountID }) {
                    accountID = accounts.accounts[(i + 1) % accounts.accounts.count].id
                }
            }
            let prompt = (args["prompt"] as? String).map { "[tarefa de \(me.name)]\n\($0)" }
            guard let pane = addPane(kind: .claude, accountID: accountID, in: ws.id, prompt: prompt, focus: false) else {
                return ("Não consegui criar o painel.", true)
            }
            if prompt != nil { terminals[pane.id]?.injectedSinceStop = true }
            let account = accounts.account(accountID)?.name ?? "?"
            return ("Criado \(pane.name) (\(account)) em \(ws.directory).", false)

        default:
            return ("Ferramenta desconhecida: \(name)", true)
        }
    }
}

enum MCPTools {
    static let instructions = """
    Você está num painel do Duo, um app com vários Claude Code lado a lado no mesmo projeto. \
    Cada painel tem um nome curto (p1, p2...). Use list_panes para ver os outros, send_to_pane para \
    pedir algo a outro painel, wait_for_pane para esperar a resposta e spawn_pane para abrir um novo \
    painel com uma tarefa. Mensagens que chegam de outro painel começam com [mensagem de pN].
    """

    static let definitions: [[String: Any]] = [
        [
            "name": "list_panes",
            "description": "Lista os painéis do workspace atual: nome, conta e estado (pronto, trabalhando, aguardando você).",
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "send_to_pane",
            "description": "Envia uma mensagem para outro painel, como se fosse digitada nele. O outro Claude Code começa a trabalhar nela.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "pane": ["type": "string", "description": "Nome do painel, ex.: p2"],
                    "message": ["type": "string", "description": "Texto da mensagem/tarefa"],
                ],
                "required": ["pane", "message"],
            ],
        ],
        [
            "name": "read_pane",
            "description": "Lê outro painel: a última resposta do Claude (padrão) ou o texto da tela.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "pane": ["type": "string"],
                    "source": ["type": "string", "enum": ["reply", "screen"]],
                    "lines": ["type": "integer", "description": "Linhas da tela (source=screen). Padrão 80."],
                ],
                "required": ["pane"],
            ],
        ],
        [
            "name": "wait_for_pane",
            "description": "Espera outro painel terminar o que está fazendo e devolve a resposta final dele.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "pane": ["type": "string"],
                    "timeout_seconds": ["type": "integer", "description": "Padrão 900."],
                ],
                "required": ["pane"],
            ],
        ],
        [
            "name": "spawn_pane",
            "description": "Abre um novo painel Claude Code no mesmo projeto, opcionalmente já com uma tarefa. Devolve o nome do painel.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string", "description": "Tarefa inicial do novo painel"],
                    "account": ["type": "string", "description": "Nome da conta, ou \"outra\". Padrão: a mesma deste painel."],
                ],
            ],
        ],
    ]
}


/// Sheet de escolha de equipe. `directory` nil = pasta ainda não escolhida (nova equipe);
/// `workspaceID` = adicionar a um workspace existente, com a pasta dele.
struct TeamSetupRequest: Identifiable {
    let id = UUID()
    let directory: String?
    let workspaceID: UUID?
}

import SwiftUI
import AppKit

struct CockpitView: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            TitleBar()
            WorkspaceTabs()
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 176)
                Rectangle().fill(Theme.bar).frame(width: 1)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Theme.bg)
        .background(WindowChrome())
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if let request = cockpit.teamSetup {
            TeamSetupView(request: request)
                .id(request.id)
        } else if let ws = workspaces.selected {
            if ws.panes.isEmpty {
                EmptyWorkspace(workspace: ws)
            } else {
                PaneGrid(workspace: ws)
            }
        } else {
            Welcome()
        }
    }
}

// MARK: Barra de título e abas

private struct TitleBar: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var updater: Updater

    var body: some View {
        HStack(spacing: 8) {
            Text("Duo").font(Theme.mono(12, .semibold)).foregroundStyle(Theme.text)
            Text(Updater.currentVersion).font(Theme.mono(11)).foregroundStyle(Theme.dim)
            if let release = updater.available {
                Button { updater.promptToUpdate(release) } label: {
                    Chip(text: "↑ \(release.version) disponível", color: Theme.accent, size: 10)
                }
                .buttonStyle(.plain)
                .disabled(updater.isBusy)
                .help("Atualizar o Duo")
            }
            Spacer()
            HStack(spacing: 14) {
                hint("⌘T", "novo painel")
                hint("⇧⌘T", "outra conta")
                hint("⌘↩", "zoom")
            }
        }
        .padding(.leading, Theme.trafficLightInset)
        .padding(.trailing, 14)
        .frame(height: 32)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.bar).frame(height: 1) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys).foregroundStyle(Theme.dim)
            Text(label).foregroundStyle(Theme.faint)
        }
        .font(Theme.mono(10))
    }
}

private struct WorkspaceTabs: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    @EnvironmentObject var accounts: AccountStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspaces.workspaces) { ws in
                WorkspaceTab(workspace: ws, isActive: ws.id == workspaces.selectedID && !cockpit.isCreatingWorkspace)
            }
            if cockpit.isCreatingWorkspace { NewTeamTab() }
            GlyphButton(glyph: "+", help: "Novo workspace (⌘N)") { cockpit.openWorkspace() }
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
            ForEach(accounts.accounts) { account in
                Button {
                    cockpit.addPane(kind: .claude, accountID: account.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(account.color).frame(width: 6, height: 6)
                        Text(account.name.uppercased())
                            .font(Theme.mono(10, .bold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(workspaces.selected == nil || cockpit.isCreatingWorkspace)
                .help("Novo Claude Code com \(account.name)")
                .overlay(alignment: .leading) { Rectangle().fill(Theme.sep).frame(width: 1) }
            }
        }
        .frame(height: 34)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent.opacity(0.1)).frame(height: 1) }
    }
}

/// Aba provisória enquanto a tela de nova equipe está aberta.
private struct NewTeamTab: View {
    @EnvironmentObject var cockpit: Cockpit

    var body: some View {
        HStack(spacing: 6) {
            Text("Nova equipe")
                .font(Theme.mono(11, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Button { cockpit.teamSetup = nil } label: {
                Text("×").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(Theme.accent.opacity(0.06))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.accent).frame(height: 2) }
    }
}

private struct WorkspaceTab: View {
    @EnvironmentObject var cockpit: Cockpit
    let workspace: Workspace
    let isActive: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Text(workspace.name)
                .font(Theme.mono(11, .bold))
                .foregroundStyle(isActive ? Theme.text : Theme.dim)
                .lineLimit(1)
            Button { cockpit.closeWorkspace(workspace.id) } label: {
                Text("×").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(isActive ? Theme.accent.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isActive ? Theme.accent : .clear).frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { cockpit.selectWorkspace(workspace.id) }
        .onHover { hover = $0 }
        .help(workspace.directory)
    }
}

// MARK: Sidebar

private struct Sidebar: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    @EnvironmentObject var accounts: AccountStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(text: "Painéis")
                Spacer()
                Menu {
                    ForEach(accounts.accounts) { account in
                        Button("Claude Code — \(account.name)") {
                            cockpit.addPane(kind: .claude, accountID: account.id)
                        }
                    }
                    Divider()
                    ForEach(accounts.accounts) { account in
                        Button("claude.ai — \(account.name)") {
                            cockpit.addPane(kind: .web, accountID: account.id)
                        }
                    }
                } label: {
                    Text("+").font(Theme.mono(12, .bold)).foregroundStyle(Theme.faint)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(workspaces.selected == nil || cockpit.isCreatingWorkspace)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.bar).frame(height: 1) }

            ScrollView {
                VStack(spacing: 0) {
                    if cockpit.isCreatingWorkspace {
                        Text("A equipe aparece aqui ao abrir.")
                            .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 10)
                    } else {
                        ForEach(Array((workspaces.selected?.panes ?? []).enumerated()), id: \.element.id) { index, pane in
                            PaneRow(pane: pane, index: index + 1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "Contas")
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                ForEach(accounts.accounts) { account in
                    AccountRow(account: account)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.bar).frame(height: 1) }

            SettingsLink {
                HStack {
                    Text("‹ AJUSTES").font(Theme.mono(9, .bold)).tracking(1.4).foregroundStyle(Theme.faint)
                    Spacer()
                    Text("⌘,").font(Theme.mono(9)).foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { Rectangle().fill(Theme.bar).frame(height: 1) }
        }
    }
}

private struct PaneRow: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    let pane: PaneSpec
    let index: Int

    var body: some View {
        let isFocused = cockpit.focusedPane == pane.id
        let account = accounts.account(pane.accountID)
        HStack(spacing: 8) {
            if pane.kind == .web {
                Circle().strokeBorder(Theme.sky, lineWidth: 1).frame(width: 6, height: 6)
            } else if let term = cockpit.terminal(pane.id) {
                TerminalStatusDot(term: term)
            } else {
                StatusDot(status: .starting)
            }
            Text(pane.name)
                .font(Theme.mono(11.5, .bold))
                .foregroundStyle(isFocused ? Theme.accentSoft : Theme.soft)
            if let role = pane.role {
                Text(role.short)
                    .font(Theme.mono(10))
                    .foregroundStyle(role.color.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text(pane.kind == .web ? "web" : (account?.name.lowercased() ?? ""))
                    .font(Theme.mono(10))
                    .foregroundStyle(account?.color.opacity(0.85) ?? Theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(index)")
                .font(Theme.mono(11))
                .foregroundStyle(isFocused ? Theme.accentSoft.opacity(0.7) : Theme.faint)
        }
        .padding(.horizontal, 10)
        .frame(height: 29)
        .background(isFocused ? Theme.accent.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { cockpit.focusedPane = pane.id }
        .help(pane.kind == .web ? "claude.ai" : pane.directory)
    }
}

private struct AccountRow: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    let account: Account

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(account.color).frame(width: 6, height: 6)
            Text(account.name.lowercased())
                .font(Theme.mono(11.5, .bold))
                .foregroundStyle(Theme.soft)
                .lineLimit(1)
            Spacer(minLength: 0)
            GlyphButton(glyph: ">_", help: "Novo Claude Code com \(account.name)", size: 10) {
                cockpit.addPane(kind: .claude, accountID: account.id)
            }
            GlyphButton(glyph: "◎", help: "claude.ai de \(account.name)", size: 11) {
                cockpit.addPane(kind: .web, accountID: account.id)
            }
        }
        .disabled(workspaces.selected == nil)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
}

// MARK: Pedaços que observam um terminal

/// Cada uma destas observa só o seu terminal: o status de um painel não redesenha os outros.
private struct TerminalStatusDot: View {
    @ObservedObject var term: TerminalSession

    var body: some View { StatusDot(status: term.status) }
}

private struct TerminalStatusChip: View {
    @ObservedObject var term: TerminalSession

    var body: some View {
        let color = Theme.color(for: term.status)
        Chip(text: term.status.label, color: color == Theme.dim ? Theme.soft : color, bold: false, size: 10)
    }
}

/// Modelo pedido para o painel; fica amarelo quando o Claude Code está rodando outro.
private struct TerminalModelChip: View {
    @ObservedObject var term: TerminalSession

    var body: some View {
        let requested = term.requestedModel ?? ""
        if term.modelMismatch {
            let actual = term.actualModel.map(Self.family) ?? "?"
            Chip(text: "pediu \(requested) · rodando \(actual)", color: Theme.yellow, bold: false, size: 10)
                .help("A conta não está usando o modelo pedido (sem acesso ou limite esgotado).")
        } else {
            Chip(text: requested, color: Theme.dim, bold: false, size: 10)
        }
    }

    /// claude-sonnet-5-5 → sonnet 5.5
    static func family(_ id: String) -> String {
        let parts = id.split(separator: "-").dropFirst()
        guard let name = parts.first else { return id }
        let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }
        return version.isEmpty ? String(name) : "\(name) \(version.joined(separator: "."))"
    }
}

private struct TerminalPaneHost: View {
    @ObservedObject var term: TerminalSession

    var body: some View {
        PaneHost(view: term.view, inset: 8)
            .id(ObjectIdentifier(term.view))
    }
}

// MARK: Grid

private struct PaneGrid: View {
    @EnvironmentObject var cockpit: Cockpit
    let workspace: Workspace

    private var visible: [PaneSpec] {
        if cockpit.zoomed, let id = cockpit.focusedPane, let pane = workspace.panes.first(where: { $0.id == id }) {
            return [pane]
        }
        return workspace.panes
    }

    /// 1 → 1, 2 → 2, 3 → 3, 4 → 2x2, 5–6 → 3x2, 7–9 → 3x3, depois 4 colunas.
    private func columns(for count: Int) -> Int {
        switch count {
        case ...3: max(count, 1)
        case 4: 2
        case 5...9: 3
        default: 4
        }
    }

    var body: some View {
        let panes = visible
        let cols = columns(for: panes.count)
        let rows = stride(from: 0, to: panes.count, by: cols).map { Array(panes[$0..<min($0 + cols, panes.count)]) }
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r]) { pane in
                        PaneView(pane: pane)
                    }
                }
            }
        }
        .padding(6)
    }
}

private struct PaneView: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    let pane: PaneSpec

    var body: some View {
        let isFocused = cockpit.focusedPane == pane.id
        let account = accounts.account(pane.accountID)
        let accent = account?.color ?? Theme.dim
        VStack(spacing: 0) {
            PaneChrome(pane: pane, account: account, isFocused: isFocused)
            if pane.isAwaitingRole {
                RolePicker(pane: pane, isFocused: isFocused)
            } else if pane.kind == .claude, let term = cockpit.terminal(pane.id) {
                TerminalPaneHost(term: term)
            } else if let view = cockpit.view(for: pane) {
                PaneHost(view: view, inset: 0)
                    .id(ObjectIdentifier(view))
            } else {
                Color.black
            }
        }
        .frame(minWidth: 0, minHeight: 0)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? accent.opacity(0.7) : Theme.paneBorder, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PaneChrome: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    let pane: PaneSpec
    let account: Account?
    let isFocused: Bool

    var body: some View {
        let accent = account?.color ?? Theme.dim
        let term = cockpit.terminal(pane.id)
        HStack(spacing: 6) {
            if pane.kind == .web {
                Circle().strokeBorder(Theme.sky, lineWidth: 1).frame(width: 6, height: 6)
            } else if let term {
                TerminalStatusDot(term: term)
            } else {
                StatusDot(status: .starting)
            }
            Chip(text: (account?.name ?? "?").uppercased(), color: accent)
            Chip(text: pane.name, color: Theme.soft, bold: false)
            if let role = pane.role {
                Chip(text: role.short, color: role.color)
            } else if pane.isAwaitingRole {
                Chip(text: "escolher papel", color: Theme.dim, bold: false, size: 10)
            }
            if let term, term.requestedModel != nil {
                TerminalModelChip(term: term)
            }
            Text(pane.kind == .web ? "claude.ai" : folderLabel)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Spacer(minLength: 4)
            if let term {
                TerminalStatusChip(term: term)
                GlyphButton(glyph: "↻", help: "Reiniciar (mantém a conversa)") { term.restart(resume: true) }
            } else if pane.kind == .web {
                let web = cockpit.web(for: pane.accountID)
                GlyphButton(glyph: "←", help: "Voltar") { web.goBack() }
                GlyphButton(glyph: "↻", help: "Recarregar") { web.reload() }
            }
            GlyphButton(glyph: cockpit.zoomed ? "⤡" : "⤢", help: "Zoom (⌘↩)") {
                cockpit.focusedPane = pane.id
                cockpit.zoomed.toggle()
            }
            GlyphButton(glyph: "×", help: "Fechar painel (⌘W)") { cockpit.closePane(pane.id) }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(Color.black.opacity(0.5))
        .overlay(alignment: .bottom) { Rectangle().fill(accent.opacity(isFocused ? 0.25 : 0.1)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { cockpit.focusedPane = pane.id }
        .contextMenu { menu }
    }

    private var folderLabel: String {
        if let branch = pane.branch { return "⎇ \(branch)" }
        return pane.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    @ViewBuilder
    private var menu: some View {
        if pane.kind == .claude, let term = cockpit.terminal(pane.id) {
            let others = (workspaces.workspace(containing: pane.id)?.panes ?? [])
                .filter { $0.id != pane.id && $0.kind == .claude }
            if !others.isEmpty {
                Menu("Enviar última resposta para") {
                    ForEach(others) { other in
                        Button(other.name) { cockpit.forwardLastReply(from: pane.id, to: other.id) }
                    }
                }
                Divider()
            }
            Button("Reiniciar e continuar conversa") { term.restart(resume: true) }
            Button("Reiniciar com conversa nova") { term.restart(resume: false) }
            Button("Mostrar pasta no Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pane.directory)
            }
            Divider()
        }
        Button("Fechar \(pane.name)") { cockpit.closePane(pane.id) }
    }
}

/// Centro de um painel aberto pelo ⌘T: escolher o papel antes de iniciar o claude.
/// Setas ou números escolhem, Enter abre, Esc fecha o painel.
private struct RolePicker: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    let pane: PaneSpec
    let isFocused: Bool

    /// nil = sem papel.
    private let options: [TeamRole?] = [nil] + TeamRole.allCases.map { $0 }
    @State private var index = 0
    @FocusState private var focused: Bool

    /// Devs que já estão no workspace (decide se um novo dev ganha worktree).
    private var devCount: Int {
        (workspaces.workspace(containing: pane.id)?.panes ?? [])
            .filter { $0.id != pane.id && $0.role?.isDev == true }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Papel de \(pane.name)").padding(.horizontal, 10).padding(.bottom, 6)
            ForEach(options.indices, id: \.self) { i in
                row(i)
            }
            Text("↑↓ ou 1–\(options.count) · ↩ abre · esc fecha")
                .font(Theme.mono(10)).foregroundStyle(Theme.faint)
                .padding(.horizontal, 10).padding(.top, 8)
        }
        .frame(width: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture {
            cockpit.focusedPane = pane.id
            focused = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { open(index); return .handled }
        .onKeyPress(.escape) { cockpit.closePane(pane.id, confirm: false); return .handled }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            guard let n = Int(press.characters), n >= 1, n <= options.count else { return .ignored }
            open(n - 1)
            return .handled
        }
        .onAppear { if isFocused { focused = true } }
        .onChange(of: isFocused) { _, now in if now { focused = true } }
    }

    private func row(_ i: Int) -> some View {
        let role = options[i]
        let active = i == index
        return HStack(spacing: 10) {
            Text("\(i + 1)").font(Theme.mono(11)).foregroundStyle(Theme.faint).frame(width: 12)
            Text(role?.title ?? "Sem papel")
                .font(Theme.mono(11.5, .bold))
                .foregroundStyle(role?.color ?? (active ? Theme.text : Theme.soft))
            Spacer(minLength: 0)
            Text(subtitle(role)).font(Theme.mono(10)).foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(active && focused ? Theme.accent.opacity(0.12)
                                                           : active ? Theme.bar : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(active ? (focused ? Theme.accent.opacity(0.45) : Theme.paneBorder) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        // O mouse move a seleção, como num menu; clique abre.
        .onHover { if $0 { index = i } }
        .onTapGesture { open(i) }
    }

    private func subtitle(_ role: TeamRole?) -> String {
        guard let role else { return "claude code comum" }
        var text = "\(role.defaultModel.rawValue) · \(role.defaultEffort.label)"
        if role.isDev, devCount >= 1 { text += " · worktree" }
        return text
    }

    private func move(_ delta: Int) {
        index = (index + delta + options.count) % options.count
    }

    private func open(_ i: Int) {
        cockpit.focusedPane = pane.id
        cockpit.chooseRole(options[i], for: pane.id)
    }
}

/// Hospeda a NSView viva de um painel (terminal ou web). A view continua existindo
/// quando o painel some da tela, então o processo não para.
private struct PaneHost: NSViewRepresentable {
    let view: NSView
    let inset: CGFloat

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.nsBg.cgColor
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard view.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.isHidden = false
        // Constraints em vez de frame: o container nasce com tamanho zero, e um frame
        // com margem calculado nessa hora vira um retângulo nulo que nunca se recupera.
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: inset * 0.75),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset * 0.75),
        ])
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}

// MARK: Estados vazios

private struct EmptyWorkspace: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(workspace.name).font(Theme.mono(14, .bold)).foregroundStyle(Theme.text)
            Text(workspace.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(Theme.mono(11)).foregroundStyle(Theme.faint)
                .padding(.bottom, 12)
            ForEach(Array(accounts.accounts.enumerated()), id: \.element.id) { index, account in
                ActionRow(keys: index == 0 ? "⌘T" : (index == 1 ? "⇧⌘T" : ""),
                          label: "claude code · \(account.name.lowercased())",
                          color: account.color) {
                    cockpit.addPane(kind: .claude, accountID: account.id)
                }
            }
            ActionRow(keys: "⇧⌘E", label: "montar equipe…", color: Theme.accent) {
                cockpit.setUpTeamInSelectedWorkspace()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct Welcome: View {
    @EnvironmentObject var cockpit: Cockpit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duo").font(Theme.mono(16, .bold)).foregroundStyle(Theme.text)
            Text("vários claude code, várias contas, um projeto.")
                .font(Theme.mono(11)).foregroundStyle(Theme.faint)
                .padding(.bottom, 12)
            ActionRow(keys: "⌘N", label: "novo workspace…", color: Theme.accent) {
                cockpit.openWorkspace()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ActionRow: View {
    let keys: String
    let label: String
    let color: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(keys).foregroundStyle(color).frame(width: 44, alignment: .leading)
                Text(label).foregroundStyle(hover ? Theme.text : Theme.soft)
                Spacer(minLength: 0)
                Text("→").foregroundStyle(hover ? color : .clear)
            }
            .font(Theme.mono(12))
            .padding(.horizontal, 10)
            .frame(width: 340, height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.bar : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hover ? Theme.paneBorder : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -10)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

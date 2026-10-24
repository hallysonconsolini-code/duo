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
                if cockpit.sidebarVisible {
                    Sidebar()
                        .frame(width: 176)
                    Rectangle().fill(Theme.bar).frame(width: 1)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottomTrailing) { NoticeStack(notices: cockpit.notices) }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cockpit.sidebarVisible)
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
            SidebarToggle()
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

private struct SidebarToggle: View {
    @EnvironmentObject var cockpit: Cockpit
    @State private var hover = false

    var body: some View {
        Button { cockpit.sidebarVisible.toggle() } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12))
                .foregroundStyle(hover ? Theme.text : Theme.faint)
                .frame(minWidth: 18, minHeight: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Mostrar/Esconder barra lateral (⌃⌘S)")
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
    @EnvironmentObject var roles: RoleStore
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
            if let roleID = pane.role {
                let role = roles.role(roleID)
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
    var hidden = false

    var body: some View {
        PaneHost(view: term.view, inset: 8, hidden: hidden)
            .id(ObjectIdentifier(term.view))
    }
}

// MARK: Grid

/// Painéis em posição absoluta dentro do espaço disponível. Cada painel é identificado
/// pelo id: mudar tamanho, abrir ou fechar outro painel só muda o frame, sem recriar a
/// view nem tirar o terminal (NSView do SwiftTerm) do lugar. No zoom, os outros painéis
/// continuam na árvore, escondidos, pelo mesmo motivo.
private struct PaneGrid: View {
    @EnvironmentObject var cockpit: Cockpit
    let workspace: Workspace

    static let spacing: CGFloat = 6
    static let padding: CGFloat = 6

    private struct Placed: Identifiable {
        let pane: PaneSpec
        let item: GridLayout.Item
        var id: UUID { pane.id }
    }

    /// Tamanho que a alça de arrastar vai aplicar ao soltar, e onde desenhar a prévia.
    private struct ResizePreview {
        let id: UUID
        let size: PaneSize
        let rect: CGRect
    }

    @State private var preview: ResizePreview?

    private var zoomedID: UUID? {
        guard cockpit.zoomed, let id = cockpit.focusedPane, workspace.panes.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    var body: some View {
        let panes = workspace.panes
        let layout = GridLayout.make(spans: panes.map { (col: $0.colSpan, row: $0.rowSpan) })
        let placed = zip(panes, layout.items).map { Placed(pane: $0, item: $1) }
        let zoomedID = zoomedID
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size).insetBy(dx: Self.padding, dy: Self.padding)
            ZStack(alignment: .topLeading) {
                ForEach(placed) { p in
                    let pane = p.pane, item = p.item
                    let hidden = zoomedID != nil && zoomedID != pane.id
                    let rect = zoomedID == pane.id
                        ? full
                        : layout.frame(of: item, in: geo.size, spacing: Self.spacing, padding: Self.padding)
                    PaneView(pane: pane, hidden: hidden, resizable: zoomedID == nil) { translation, ended in
                        resize(pane, from: rect, by: translation, ended: ended, bounds: full)
                    }
                        .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(hidden ? 0 : 1)
                        .allowsHitTesting(!hidden)
                        .zIndex(zoomedID == pane.id ? 1 : 0)
                }
                if let preview, zoomedID == nil {
                    ResizePreviewOutline(size: preview.size)
                        .frame(width: preview.rect.width, height: preview.rect.height)
                        .position(x: preview.rect.midX, y: preview.rect.midY)
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    /// Alça de arrastar: passar de 1/4 do painel para a direita/baixo pede 2 células naquela
    /// direção; para a esquerda/cima, 1. A prévia é aproximada (o grid se reorganiza ao soltar).
    private func resize(_ pane: PaneSpec, from rect: CGRect, by t: CGSize, ended: Bool, bounds: CGRect) {
        let current = pane.size
        var cols = current.colSpan, rows = current.rowSpan
        if t.width > rect.width / 4 { cols = 2 } else if t.width < -rect.width / 4 { cols = 1 }
        if t.height > rect.height / 4 { rows = 2 } else if t.height < -rect.height / 4 { rows = 1 }
        let target = PaneSize(colSpan: cols, rowSpan: rows)
        if ended {
            preview = nil
            if target != current { cockpit.setSize(target, for: pane.id) }
            return
        }
        func scaled(_ length: CGFloat, from a: Int, to b: Int) -> CGFloat {
            b > a ? length * 2 + Self.spacing : (b < a ? (length - Self.spacing) / 2 : length)
        }
        let size = CGSize(width: scaled(rect.width, from: current.colSpan, to: cols),
                          height: scaled(rect.height, from: current.rowSpan, to: rows))
        let outline = CGRect(origin: rect.origin, size: size).intersection(bounds)
        preview = ResizePreview(id: pane.id, size: target, rect: outline.isNull ? rect : outline)
    }
}

/// Contorno mostrado enquanto a alça é arrastada, com o tamanho que será aplicado.
private struct ResizePreviewOutline: View {
    let size: PaneSize

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.accent.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .overlay { Chip(text: size.label, color: Theme.accent) }
    }
}

private struct PaneView: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    let pane: PaneSpec
    /// Escondido atrás do painel em zoom: continua montado, com a NSView oculta.
    var hidden = false
    /// Mostra a alça de arrastar no canto inferior direito.
    var resizable = false
    /// Arrasto da alça: deslocamento desde o clique e se o botão foi solto.
    var onResize: (CGSize, Bool) -> Void = { _, _ in }

    var body: some View {
        let isFocused = cockpit.focusedPane == pane.id
        let account = accounts.account(pane.accountID)
        let accent = account?.color ?? Theme.dim
        VStack(spacing: 0) {
            PaneChrome(pane: pane, account: account, isFocused: isFocused)
            if pane.isAwaitingRole {
                RolePicker(pane: pane, isFocused: isFocused)
            } else if pane.kind == .claude, let term = cockpit.terminal(pane.id) {
                TerminalPaneHost(term: term, hidden: hidden)
            } else if let view = cockpit.view(for: pane) {
                PaneHost(view: view, inset: 0, hidden: hidden)
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
        .overlay(alignment: .bottomTrailing) {
            // NSView própria: fica acima da NSView do terminal na ordem do AppKit e recebe o clique.
            ResizeHandle(hidden: hidden || !resizable, onDrag: onResize)
                .frame(width: 14, height: 14)
        }
    }
}

private struct PaneChrome: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var roles: RoleStore
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
            if let roleID = pane.role {
                let role = roles.role(roleID)
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
            PaneSizeButton(pane: pane)
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
        Menu("Tamanho") {
            ForEach(PaneSize.allCases, id: \.self) { size in
                Toggle(size.label, isOn: Binding(
                    get: { pane.size == size },
                    set: { _ in cockpit.setSize(size, for: pane.id) }
                ))
            }
            Divider()
            Button("Aumentar") { cockpit.setSize(pane.size.bigger, for: pane.id) }
                .keyboardShortcut("=", modifiers: [.command, .control])
                .disabled(pane.size.bigger == pane.size)
            Button("Diminuir") { cockpit.setSize(pane.size.smaller, for: pane.id) }
                .keyboardShortcut("-", modifiers: [.command, .control])
                .disabled(pane.size.smaller == pane.size)
        }
        Divider()
        Button("Fechar \(pane.name)") { cockpit.closePane(pane.id) }
    }
}

/// Botão do topo do painel que abre os tamanhos prontos numa lista do Duo.
private struct PaneSizeButton: View {
    @EnvironmentObject var cockpit: Cockpit
    let pane: PaneSpec
    @State private var open = false

    var body: some View {
        GlyphButton(glyph: "⊞", help: "Tamanho: \(pane.size.label) (⌃⌘= / ⌃⌘−)") { open.toggle() }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                DuoMenuList(
                    options: PaneSize.allCases.map { .init(value: $0, label: $0.title, detail: "\($0.colSpan)×\($0.rowSpan)") },
                    selection: pane.size,
                    minWidth: 150
                ) { size in
                    cockpit.setSize(size, for: pane.id)
                    open = false
                }
            }
    }
}

/// Centro de um painel aberto pelo ⌘T: escolher o papel antes de iniciar o claude.
/// Setas ou números escolhem, Enter abre, Esc fecha o painel.
private struct RolePicker: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    @EnvironmentObject var roles: RoleStore
    let pane: PaneSpec
    let isFocused: Bool

    /// nil = sem papel.
    private var options: [Role?] { [nil] + roles.all.map { $0 } }
    @State private var index = 0
    @FocusState private var focused: Bool

    /// Quem já edita código no workspace (decide se o novo ganha worktree).
    private var devCount: Int {
        (workspaces.workspace(containing: pane.id)?.panes ?? [])
            .filter { $0.id != pane.id && $0.role.map { roles.role($0).editsCode } == true }.count
    }

    var body: some View {
        // Cabe: lista centrada como antes. Não cabe: a lista rola e o título e a dica ficam fixos.
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 2) {
                title
                rows
                hint
            }
            VStack(alignment: .leading, spacing: 2) {
                title
                ScrollViewReader { proxy in
                    ScrollView { rows }
                        .onChange(of: index) { _, i in proxy.scrollTo(i) }
                }
                hint
            }
            .padding(.vertical, 12)
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
            guard let n = Int(press.characters), n >= 1, n <= min(options.count, 9) else { return .ignored }
            open(n - 1)
            return .handled
        }
        .onAppear { if isFocused { focused = true } }
        .onChange(of: isFocused) { _, now in if now { focused = true } }
    }

    private var title: some View {
        SectionLabel(text: "Papel de \(pane.name)").padding(.horizontal, 10).padding(.bottom, 6)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                row(i).id(i)
            }
        }
    }

    private var hint: some View {
        Text("↑↓ ou 1–\(min(options.count, 9)) · ↩ abre · esc fecha")
            .font(Theme.mono(10)).foregroundStyle(Theme.faint)
            .padding(.horizontal, 10).padding(.top, 8)
    }

    private func row(_ i: Int) -> some View {
        let role = options[i]
        let active = i == index
        return HStack(spacing: 8) {
            Text(i < 9 ? "\(i + 1)" : " ").font(Theme.mono(11)).foregroundStyle(Theme.faint).frame(width: 12)
            Group {
                if let role {
                    RoleIcon(role: role, size: 12)
                } else {
                    Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(Theme.dim)
                        .frame(width: 18, height: 14.4)
                }
            }
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

    private func subtitle(_ role: Role?) -> String {
        guard let role else { return "claude code comum" }
        var text = "\(role.defaultModel.rawValue) · \(role.defaultEffort.label)"
        if role.editsCode, devCount >= 1 { text += " · worktree" }
        return text
    }

    private func move(_ delta: Int) {
        index = (index + delta + options.count) % options.count
    }

    private func open(_ i: Int) {
        cockpit.focusedPane = pane.id
        cockpit.chooseRole(options[i]?.id, for: pane.id)
    }
}

/// Alça de redimensionar no canto do painel. É uma NSView para receber o clique mesmo
/// estando por cima do terminal (que também é NSView).
private struct ResizeHandle: NSViewRepresentable {
    var hidden: Bool
    let onDrag: (CGSize, Bool) -> Void

    func makeNSView(context: Context) -> ResizeHandleView { ResizeHandleView() }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.onDrag = onDrag
        if view.isHidden != hidden { view.isHidden = hidden }
    }
}

final class ResizeHandleView: NSView {
    var onDrag: ((CGSize, Bool) -> Void)?
    private var start: NSPoint?
    private var hover = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        let cursor: NSCursor
        if #available(macOS 15, *) {
            cursor = .frameResize(position: .bottomRight, directions: .all)
        } else {
            cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }

    override func mouseDown(with event: NSEvent) { start = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onDrag?(delta(event, start), false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        self.start = nil
        onDrag?(delta(event, start), true)
    }

    /// Em coordenadas de janela o y cresce para cima; aqui, para baixo (como no SwiftUI).
    private func delta(_ event: NSEvent, _ start: NSPoint) -> CGSize {
        CGSize(width: event.locationInWindow.x - start.x, height: start.y - event.locationInWindow.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Três traços diagonais, como a alça de redimensionar do macOS.
        let color = (hover || start != nil) ? Theme.nsText.withAlphaComponent(0.8) : Theme.nsText.withAlphaComponent(0.3)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        let w = bounds.width, h = bounds.height
        for k in [4.0, 7.5, 11.0] {
            path.move(to: NSPoint(x: w - 2, y: h - 2 - k))
            path.line(to: NSPoint(x: w - 2 - k, y: h - 2))
        }
        path.stroke()
    }
}

/// Hospeda a NSView viva de um painel (terminal ou web). A view continua existindo
/// quando o painel some da tela, então o processo não para.
private struct PaneHost: NSViewRepresentable {
    let view: NSView
    let inset: CGFloat
    /// Oculta a view sem tirá-la do container (painel atrás do zoom). Oculta, ela não
    /// recebe clique nem é escolhida pelo foco por clique (`isHiddenOrHasHiddenAncestor`).
    var hidden = false

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.nsBg.cgColor
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if container.isHidden != hidden { container.isHidden = hidden }
        if view.superview === container {
            if view.isHidden != hidden { view.isHidden = hidden }
            return
        }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.isHidden = hidden
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

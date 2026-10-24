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
            SidebarToggle()
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
                hint("⌘D", "dividir")
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

// MARK: Painéis (divisões livres)

/// Painéis em posição absoluta, nos retângulos da árvore de divisões do workspace. Cada painel
/// é identificado pelo id: arrastar divisória, mover, abrir ou fechar outro painel só muda o
/// frame, sem recriar a view nem tirar o terminal (NSView do SwiftTerm) do lugar. No zoom, os
/// outros painéis continuam na árvore, escondidos, pelo mesmo motivo.
private struct PaneGrid: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    let workspace: Workspace

    /// Layout durante o arrasto de uma divisória (gravado só ao soltar).
    @State private var live: SplitNode?
    /// Layout e retângulo da divisão quando o arrasto começou.
    @State private var dragStart: (layout: SplitNode, splitRect: CGRect)?
    /// Painel sendo arrastado pela barra e onde ele cairia.
    @State private var move: PaneMove?

    private struct PaneMove: Equatable {
        let pane: UUID
        var target: UUID?
        var edge: SplitNode.Edge = .right
    }

    private var zoomedID: UUID? {
        guard cockpit.zoomed, let id = cockpit.focusedPane, workspace.panes.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Sempre com os painéis do workspace (o store já mantém assim; isto é só a rede de segurança).
    private var layout: SplitNode? {
        let ids = workspace.panes.map(\.id)
        if let live, Set(live.paneIDs) == Set(ids) { return live }
        return SplitNode.reconciled(workspace.layout, with: ids, bounds: workspaces.layoutBounds)
    }

    var body: some View {
        let panes = workspace.panes
        let layout = layout
        let zoomedID = zoomedID
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size).insetBy(dx: SplitNode.padding, dy: SplitNode.padding)
            let frames = layout?.frames(in: full) ?? [:]
            ZStack(alignment: .topLeading) {
                PaneArea(chromes: zoomedID == nil && panes.count > 1 ? Self.chromeRects(frames) : [:]) { id, location, ended in
                    dragPane(id, to: location, ended: ended, frames: frames)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                ForEach(panes) { pane in
                    let hidden = zoomedID != nil && zoomedID != pane.id
                    let rect = zoomedID == pane.id ? full : (frames[pane.id] ?? .zero)
                    PaneView(pane: pane, hidden: hidden, isMoving: move?.pane == pane.id)
                    .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(hidden ? 0 : 1)
                    .allowsHitTesting(!hidden)
                    .zIndex(zoomedID == pane.id ? 1 : 0)
                }
                if zoomedID == nil, let layout {
                    ForEach(layout.dividers(in: full)) { divider in
                        DividerHandle(axis: divider.axis) { phase in
                            dragDivider(divider, phase)
                        }
                        .frame(width: divider.rect.width, height: divider.rect.height)
                        .position(x: divider.rect.midX, y: divider.rect.midY)
                        .zIndex(2)
                    }
                }
                if let move, let target = move.target, let rect = frames[target] {
                    DropHighlight()
                        .frame(width: Self.dropRect(rect, move.edge).width, height: Self.dropRect(rect, move.edge).height)
                        .position(x: Self.dropRect(rect, move.edge).midX, y: Self.dropRect(rect, move.edge).midY)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .onAppear { workspaces.layoutBounds = full.size }
            .onChange(of: geo.size) { _, size in
                workspaces.layoutBounds = CGSize(width: size.width - 2 * SplitNode.padding,
                                                 height: size.height - 2 * SplitNode.padding)
            }
        }
    }

    private func dragDivider(_ divider: SplitNode.Divider, _ phase: DividerHandleView.Phase) {
        switch phase {
        case .began:
            guard let layout else { return }
            dragStart = (layout, divider.splitRect)
        case .moved(let delta):
            guard let start = dragStart else { return }
            live = start.layout.resizing(path: divider.path, index: divider.index, by: delta, in: start.splitRect)
        case .ended:
            if let live { cockpit.setLayout(live, in: workspace.id) }
            live = nil
            dragStart = nil
        case .doubleClick:
            guard let layout else { return }
            cockpit.setLayout(layout.balanced(at: divider.path), in: workspace.id)
        }
    }

    /// Arrastar a barra de um painel: o painel sob o mouse é o alvo, e a borda mais próxima
    /// do mouse diz de que lado o painel arrastado entra.
    private func dragPane(_ id: UUID, to location: CGPoint, ended: Bool, frames: [UUID: CGRect]) {
        guard zoomedID == nil, workspace.panes.count > 1 else { move = nil; return }
        var next = PaneMove(pane: id)
        if let (target, rect) = frames.first(where: { $0.key != id && $0.value.contains(location) }) {
            let dx = (location.x - rect.minX) / max(rect.width, 1)
            let dy = (location.y - rect.minY) / max(rect.height, 1)
            let distances: [(SplitNode.Edge, CGFloat)] = [(.left, dx), (.right, 1 - dx), (.top, dy), (.bottom, 1 - dy)]
            next.target = target
            next.edge = distances.min { $0.1 < $1.1 }!.0
        }
        if ended {
            move = nil
            if let target = next.target { cockpit.movePane(id, to: next.edge, of: target) }
        } else if move != next {
            move = next
        }
    }

    /// Barra de cada painel (de onde se arrasta o painel).
    static func chromeRects(_ frames: [UUID: CGRect]) -> [UUID: CGRect] {
        frames.mapValues { CGRect(x: $0.minX, y: $0.minY, width: $0.width, height: min(PaneChrome.height, $0.height)) }
    }

    /// Metade do alvo do lado onde o painel vai entrar.
    static func dropRect(_ rect: CGRect, _ edge: SplitNode.Edge) -> CGRect {
        switch edge {
        case .left: CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right: CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .bottom: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        }
    }
}

/// Onde o painel arrastado vai cair. É uma NSView para ficar acima das NSViews dos terminais.
private struct DropHighlight: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1.5
        view.layer?.borderColor = NSColor(Theme.accent).withAlphaComponent(0.85).cgColor
        view.layer?.backgroundColor = NSColor(Theme.accent).withAlphaComponent(0.14).cgColor
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    /// Não pega o mouse.
    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Fundo da área dos painéis. Marca a área para o Cockpit (clicar e arrastar ali não move a
/// janela) e acompanha o arrasto que começa na barra de um painel. O arrasto é lido por um
/// monitor de eventos, sem consumir nada: os botões da barra e os terminais continuam
/// recebendo o mouse normalmente, e o painel só começa a ser movido depois de alguns pontos.
private struct PaneArea: NSViewRepresentable {
    @EnvironmentObject var cockpit: Cockpit
    /// Barra de cada painel, no espaço desta view (origem no canto superior esquerdo).
    let chromes: [UUID: CGRect]
    /// Painel arrastado, posição do mouse e se o botão foi solto.
    let onMove: (UUID, CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> PaneAreaView { PaneAreaView() }

    func updateNSView(_ view: PaneAreaView, context: Context) {
        view.chromes = chromes
        view.onMove = onMove
        if cockpit.paneArea !== view { cockpit.paneArea = view }
    }
}

final class PaneAreaView: NSView {
    var chromes: [UUID: CGRect] = [:]
    var onMove: ((UUID, CGPoint, Bool) -> Void)?
    private var monitor: Any?
    private var pressed: (pane: UUID, at: CGPoint)?
    private var moving = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.window === window, window != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            pressed = nil
            moving = false
            guard !isHiddenOrHasHiddenAncestor, event.clickCount == 1,
                  let id = chromes.first(where: { $0.value.contains(point) })?.key else { return }
            pressed = (id, point)
        case .leftMouseDragged:
            guard let pressed else { return }
            if !moving, hypot(point.x - pressed.at.x, point.y - pressed.at.y) < 6 { return }
            moving = true
            NSCursor.closedHand.set()
            onMove?(pressed.pane, point, false)
        case .leftMouseUp:
            if let pressed, moving {
                onMove?(pressed.pane, point, true)
                NSCursor.arrow.set()
            }
            pressed = nil
            moving = false
        default:
            break
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

private struct PaneView: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    let pane: PaneSpec
    /// Escondido atrás do painel em zoom: continua montado, com a NSView oculta.
    var hidden = false
    /// Sendo arrastado pela barra para outro lugar.
    var isMoving = false

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
                .strokeBorder(isMoving ? Theme.accent.opacity(0.8) : isFocused ? accent.opacity(0.7) : Theme.paneBorder,
                              style: StrokeStyle(lineWidth: 1, dash: isMoving ? [5, 4] : []))
        )
    }
}

private struct PaneChrome: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var roles: RoleStore
    @EnvironmentObject var workspaces: WorkspaceStore
    let pane: PaneSpec
    let account: Account?
    let isFocused: Bool

    static let height: CGFloat = 32

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
            GlyphButton(glyph: cockpit.zoomed ? "⤡" : "⤢", help: "Zoom (⌘↩)") {
                cockpit.focusedPane = pane.id
                cockpit.zoomed.toggle()
            }
            GlyphButton(glyph: "×", help: "Fechar painel (⌘W)") { cockpit.closePane(pane.id) }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
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
        Button("Dividir à direita") {
            cockpit.focusedPane = pane.id
            cockpit.splitFocusedPane(.right)
        }
        Button("Dividir abaixo") {
            cockpit.focusedPane = pane.id
            cockpit.splitFocusedPane(.bottom)
        }
        Button("Equilibrar painéis") { cockpit.balanceLayout() }
        Divider()
        Button("Fechar \(pane.name)") { cockpit.closePane(pane.id) }
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

/// Divisória entre dois painéis vizinhos. É uma NSView para receber o mouse e mostrar o
/// cursor de redimensionar mesmo ao lado das NSViews dos terminais.
private struct DividerHandle: NSViewRepresentable {
    let axis: SplitNode.Axis
    let onEvent: (DividerHandleView.Phase) -> Void

    func makeNSView(context: Context) -> DividerHandleView { DividerHandleView() }

    func updateNSView(_ view: DividerHandleView, context: Context) {
        view.onEvent = onEvent
        if view.axis != axis {
            view.axis = axis
            view.window?.invalidateCursorRects(for: view)
        }
    }
}

final class DividerHandleView: NSView {
    enum Phase {
        case began
        /// Deslocamento ao longo do eixo desde o clique (x para a direita, y para baixo).
        case moved(CGFloat)
        case ended
        case doubleClick
    }

    var axis: SplitNode.Axis = .horizontal { didSet { needsDisplay = true } }
    var onEvent: ((Phase) -> Void)?
    private var start: NSPoint?
    private var hover = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var cursor: NSCursor { axis == .horizontal ? .resizeLeftRight : .resizeUpDown }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            start = nil
            onEvent?(.doubleClick)
            return
        }
        start = event.locationInWindow
        onEvent?(.began)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        cursor.set()
        // Em coordenadas de janela o y cresce para cima; aqui, para baixo (como no SwiftUI).
        let delta = axis == .horizontal ? event.locationInWindow.x - start.x : start.y - event.locationInWindow.y
        onEvent?(.moved(delta))
    }

    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        needsDisplay = true
        onEvent?(.ended)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hover || start != nil else { return }
        Theme.nsText.withAlphaComponent(start != nil ? 0.45 : 0.25).setFill()
        let line = axis == .horizontal
            ? NSRect(x: bounds.midX - 1, y: 0, width: 2, height: bounds.height)
            : NSRect(x: 0, y: bounds.midY - 1, width: bounds.width, height: 2)
        NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
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

import SwiftUI

/// Itens de layout do menu Painel e do menu de contexto da barra do painel: os modelos de
/// zonas (o atual marcado), equilibrar e remover zonas vazias.
struct LayoutMenuItems: View {
    @ObservedObject var cockpit: Cockpit
    @ObservedObject var workspaces: WorkspaceStore
    /// Observado para a lista mudar ao salvar ou apagar um modelo.
    @ObservedObject private var layouts: LayoutStore

    init(cockpit: Cockpit, workspaces: WorkspaceStore) {
        self.cockpit = cockpit
        self.workspaces = workspaces
        layouts = cockpit.layouts
    }

    var body: some View {
        let current = workspaces.selected?.zoneLayout
        ForEach(cockpit.zoneTemplates) { template in
            Toggle(template.name, isOn: Binding(
                get: { current.map { template.layout.hasSameShape(as: $0) } ?? false },
                set: { _ in cockpit.applyTemplate(template) }
            ))
        }
        Divider()
        Button("Equilibrar zonas") { cockpit.balanceZones() }
        Button("Remover zonas vazias") { cockpit.removeEmptyZones() }
            .disabled(!(workspaces.selected.map(Self.hasEmptyZone) ?? false))
    }

    static func hasEmptyZone(_ ws: Workspace) -> Bool {
        ws.zoneLayout.zoneIDs.contains { z in !ws.panes.contains { $0.zone == z } }
    }
}

// MARK: Modelos salvos

/// Modelos de zonas salvos pelo usuário, em layouts.json (como teams.json e roles.json).
@MainActor
final class LayoutStore: ObservableObject {
    @Published var custom: [ZoneTemplate] {
        didSet { save() }
    }

    private static let file = Paths.appSupport.appendingPathComponent("layouts.json")

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let decoded = try? JSONDecoder().decode([ZoneTemplate].self, from: data) {
            custom = decoded
        } else {
            custom = []
        }
    }

    var all: [ZoneTemplate] { ZoneTemplate.builtIn + custom }

    /// Salva a forma das zonas (os ids são trocados por novos ao aplicar).
    @discardableResult
    func save(name: String, layout: SplitNode) -> ZoneTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = ZoneTemplate(id: UUID().uuidString,
                                    name: trimmed.isEmpty ? "Layout \(custom.count + 1)" : trimmed,
                                    layout: layout.withFreshIDs())
        custom.append(template)
        return template
    }

    func remove(_ id: String) {
        custom.removeAll { $0.id == id }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(custom).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("Duo: falha ao salvar layouts: \(error)")
        }
    }
}

// MARK: Botão e painel de layouts

/// Botão da barra de título que abre o painel de layouts do workspace atual.
struct LayoutButton: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var workspaces: WorkspaceStore
    @State private var open = false
    @State private var hover = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 12))
                .foregroundStyle(open ? Theme.accent : hover ? Theme.text : Theme.faint)
                .frame(minWidth: 18, minHeight: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Layout das zonas")
        .disabled(workspaces.selected == nil || cockpit.teamSetup != nil)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            LayoutPanel(cockpit: cockpit, layouts: cockpit.layouts, workspaces: workspaces) { open = false }
        }
    }
}

/// Miniaturas dos modelos (clique aplica no workspace atual), salvar o layout atual como
/// modelo e apagar os salvos. Visual do Duo, dentro de um popover.
struct LayoutPanel: View {
    @ObservedObject var cockpit: Cockpit
    @ObservedObject var layouts: LayoutStore
    @ObservedObject var workspaces: WorkspaceStore
    let close: () -> Void

    @State private var naming = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private let columns = [GridItem(.fixed(112), spacing: 8), GridItem(.fixed(112), spacing: 8), GridItem(.fixed(112), spacing: 8)]

    var body: some View {
        let current = workspaces.selected?.zoneLayout
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Layout")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(layouts.all) { template in
                    LayoutTile(template: template,
                               active: current.map { template.layout.hasSameShape(as: $0) } ?? false,
                               deletable: !template.isBuiltIn,
                               pick: {
                                   cockpit.applyTemplate(template)
                                   close()
                               },
                               delete: { layouts.remove(template.id) })
                }
            }
            Rectangle().fill(Theme.bar).frame(height: 1)
            if naming {
                HStack(spacing: 6) {
                    TextField("Nome do modelo", text: $name)
                        .textFieldStyle(.plain)
                        .duoField()
                        .focused($nameFocused)
                        .onSubmit(saveCurrent)
                        .onKeyPress(.escape) { naming = false; return .handled }
                    Button("Salvar", action: saveCurrent).buttonStyle(.duo(.primary))
                    Button("Cancelar") { naming = false }.buttonStyle(.duo(.ghost))
                }
            } else {
                HStack(spacing: 6) {
                    Button("Salvar layout atual como modelo…") {
                        name = ""
                        naming = true
                        DispatchQueue.main.async { nameFocused = true }
                    }
                    .buttonStyle(.duo(.ghost))
                    .disabled(current == nil)
                    Spacer(minLength: 0)
                    Button("Equilibrar") { cockpit.balanceZones() }.buttonStyle(.duo(.ghost))
                }
            }
        }
        .padding(12)
        .frame(width: 3 * 112 + 2 * 8 + 24)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func saveCurrent() {
        guard let current = workspaces.selected?.zoneLayout else { return }
        layouts.save(name: name, layout: current)
        naming = false
    }
}

/// Uma miniatura: os retângulos das zonas do modelo e o nome.
private struct LayoutTile: View {
    let template: ZoneTemplate
    let active: Bool
    let deletable: Bool
    let pick: () -> Void
    let delete: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 5) {
                LayoutThumbnail(layout: template.layout, lit: active || hover)
                    .frame(width: 112 - 12, height: 56)
                Text(template.name)
                    .font(Theme.mono(10, active ? .bold : .regular))
                    .foregroundStyle(active || hover ? Theme.text : Theme.soft)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(6)
            .frame(width: 112, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.bar : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(active ? Theme.accent.opacity(0.7) : hover ? Theme.paneBorder : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .overlay(alignment: .topTrailing) {
            if deletable && hover {
                GlyphButton(glyph: "×", help: "Apagar modelo", size: 11, action: delete)
                    .padding(2)
            }
        }
    }
}

/// Os retângulos das zonas, desenhados.
struct LayoutThumbnail: View {
    let layout: SplitNode
    var lit = false

    var body: some View {
        Canvas { context, size in
            let frames = layout.frames(in: CGRect(origin: .zero, size: size), spacing: 3)
            for rect in frames.values {
                let path = Path(roundedRect: rect, cornerRadius: 2.5)
                context.fill(path, with: .color(lit ? Theme.accent.opacity(0.16) : Theme.bar))
                context.stroke(path, with: .color(lit ? Theme.accent.opacity(0.8) : Theme.dim.opacity(0.6)), lineWidth: 1)
            }
        }
    }
}

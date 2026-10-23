import SwiftUI

/// Editor de papel, no lugar da lista de equipes dentro da tela de nova equipe (sem sheet).
/// Papel do Duo: salva como edição (com "Restaurar padrão"). Papel novo: cria um customizado.
struct RoleEditor: View {
    @EnvironmentObject var roles: RoleStore
    let isNew: Bool
    let onClose: () -> Void

    @State private var draft: Role
    @State private var shortAuto: Bool
    @State private var confirmingDelete = false

    /// Ícones para papéis: os do Duo primeiro, depois os de uso geral. Todos existem no macOS 14.
    private static let symbols = [
        "person.fill", "list.bullet.clipboard", "chevron.left.forwardslash.chevron.right", "paintpalette",
        "checkmark.seal", "briefcase", "chart.bar", "doc.text", "megaphone", "magnifyingglass", "hammer",
        "wrench", "gearshape", "server.rack", "cloud", "lock.shield", "ladybug", "testtube.2", "lightbulb",
        "book", "bubble.left",
    ]

    /// Cores que combinam com o Theme (as dos papéis do Duo + sky, laranja e violeta).
    private static let colors = [
        "#FECACA", "#F472B6", "#FB923C", "#FACC15", "#86EFAC", "#34D399", "#38BDF8", "#A78BFA",
    ]

    private static let starterInstructions = """
        Você é um membro da equipe com este papel: descreva aqui o que ele faz.
        - Faça só o que foi pedido.
        - Se algo estiver ambíguo, pergunte a quem passou a tarefa.
        - Termine com um resumo curto: o que foi feito e o que ficou pendente.
        """

    init(role: Role, isNew: Bool, onClose: @escaping () -> Void) {
        var role = role
        if isNew {
            role.title = ""
            role.short = ""
            role.instructions = Self.starterInstructions
        }
        _draft = State(initialValue: role)
        _shortAuto = State(initialValue: role.short == role.title.lowercased())
        self.isNew = isNew
        self.onClose = onClose
    }

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBar
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    labeled("nome") {
                        TextField("Ex.: Redator", text: $draft.title)
                            .textFieldStyle(.plain).duoField()
                            .onChange(of: draft.title) { _, title in
                                if shortAuto { draft.short = title.lowercased() }
                            }
                    }
                    labeled("nome curto", hint: "aparece em list_panes e nos chips") {
                        TextField("minúsculas", text: Binding(get: { draft.short }, set: {
                            draft.short = $0
                            shortAuto = false
                        }))
                        .textFieldStyle(.plain).duoField()
                    }
                    labeled("o que faz", hint: "uma linha; o gerente usa isso para saber o que delegar") {
                        TextField("Ex.: escreve e revisa textos", text: $draft.blurb)
                            .textFieldStyle(.plain).duoField()
                    }
                }
                preview
            }
            labeled("ícone") { symbolGrid }
            HStack(alignment: .top, spacing: 28) {
                labeled("selo", hint: "até 3 letras, opcional") {
                    TextField("SR", text: Binding(get: { draft.badge ?? "" }, set: {
                        let value = String($0.uppercased().prefix(3))
                        draft.badge = value.isEmpty ? nil : value
                    }))
                    .textFieldStyle(.plain).duoField(width: 64)
                }
                labeled("cor") { colorRow }
            }
            HStack(alignment: .top, spacing: 28) {
                labeled("modelo padrão") {
                    SegmentedChoice(options: AIModel.allCases, selection: $draft.defaultModel,
                                    label: { $0.rawValue }, tint: draft.color)
                }
                labeled("esforço padrão") {
                    SegmentedChoice(options: Effort.allCases, selection: $draft.defaultEffort,
                                    label: { $0.label }, tint: draft.color)
                }
                labeled("escreve código", hint: "ganha cópia própria do repositório (worktree) e faz commit") {
                    SegmentedChoice(options: [false, true], selection: $draft.editsCode,
                                    label: { $0 ? "sim" : "não" }, tint: draft.color)
                }
            }
            labeled("instruções", hint: "A parte de equipe e comunicação é adicionada automaticamente.") {
                TextEditor(text: $draft.instructions)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 200)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bar))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.paneBorder, lineWidth: 1))
            }
            actions
        }
        .padding(16)
    }

    // MARK: Partes

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("← Voltar", action: onClose).buttonStyle(.duo(.ghost))
            Text(isNew ? "Novo papel" : "Editar papel")
                .font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
    }

    private func labeled<Content: View>(_ title: String, hint: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(Theme.mono(9, .bold)).tracking(1.2).foregroundStyle(Theme.faint)
            content()
            if let hint {
                Text(hint).font(Theme.mono(10)).foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// O card como aparece na Composição, ao vivo.
    private var preview: some View {
        let name = draft.title.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 6) {
            RoleIcon(role: draft, size: 22).padding(.top, 4).padding(.bottom, 2)
            Text(name.isEmpty ? "Sem nome" : name)
                .font(Theme.mono(11.5, .bold)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(draft.blurb.isEmpty ? " " : draft.blurb)
                .font(Theme.mono(10)).foregroundStyle(Theme.soft)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text("\(draft.defaultModel.rawValue) · \(draft.defaultEffort.label)")
                .font(Theme.mono(9.5)).foregroundStyle(Theme.faint).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: 124, height: 120)
        .background(RoundedRectangle(cornerRadius: 10).fill(draft.color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(draft.color.opacity(0.4), lineWidth: 1))
    }

    private var symbolGrid: some View {
        let symbols = Self.symbols.contains(draft.symbol) ? Self.symbols : [draft.symbol] + Self.symbols
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(symbols, id: \.self) { symbol in
                SymbolCell(symbol: symbol, tint: draft.color, active: symbol == draft.symbol) {
                    draft.symbol = symbol
                }
            }
        }
    }

    private var colorRow: some View {
        let colors = Self.colors.contains(draft.colorHex) ? Self.colors : [draft.colorHex] + Self.colors
        return HStack(spacing: 8) {
            ForEach(colors, id: \.self) { hex in
                Button { draft.colorHex = hex } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Theme.text, lineWidth: hex == draft.colorHex ? 2 : 0).padding(-3))
                        .frame(width: 24, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if !isNew {
                if draft.isBuiltIn {
                    if roles.isEdited(draft.id) {
                        Button("Restaurar padrão") {
                            roles.restore(draft.id)
                            onClose()
                        }
                        .buttonStyle(.duo(.ghost))
                    }
                } else if confirmingDelete {
                    Text("Apagar este papel?").font(Theme.mono(11)).foregroundStyle(Theme.soft)
                    Button { delete() } label: { Text("Apagar").foregroundStyle(Theme.accent) }
                        .buttonStyle(.duo(.ghost))
                    Button("Manter") { confirmingDelete = false }.buttonStyle(.duo(.ghost))
                } else {
                    Button { confirmingDelete = true } label: { Text("Apagar papel").foregroundStyle(Theme.accent) }
                        .buttonStyle(.duo(.ghost))
                }
            }
            Spacer(minLength: 0)
            Button("Cancelar", action: onClose)
                .buttonStyle(.duo(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Salvar", action: save)
                .buttonStyle(.duo(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    // MARK: Ações

    private func save() {
        guard canSave else { return }
        var role = draft
        role.title = role.title.trimmingCharacters(in: .whitespaces)
        role.short = role.short.trimmingCharacters(in: .whitespaces)
        if role.short.isEmpty { role.short = role.title.lowercased() }
        role.blurb = role.blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        role.instructions = role.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNew { roles.create(role) } else { roles.update(role) }
        onClose()
    }

    private func delete() {
        roles.delete(draft.id)
        onClose()
    }
}

private struct SymbolCell: View {
    let symbol: String
    let tint: Color
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? tint : (hover ? Theme.soft : Theme.dim))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 5).fill(active ? tint.opacity(0.14) : (hover ? Theme.bar : .clear)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(active ? tint.opacity(0.4) : Theme.paneBorder.opacity(0.6), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

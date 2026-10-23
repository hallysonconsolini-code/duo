import SwiftUI

/// Tela de nova equipe, na área central: escolher a pasta do projeto e um painel só, um template de equipe
/// ou uma equipe montada, com conta, modelo e esforço de cada membro. Pasta e equipe em
/// qualquer ordem. Ao adicionar equipe a um workspace existente, a pasta é a dele.
struct TeamSetupView: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    @EnvironmentObject var teams: TeamStore
    let request: TeamSetupRequest

    private enum Choice: Hashable {
        case single
        case template(UUID)
        case custom
    }

    @State private var choice: Choice = .template(TeamTemplate.standard.id)
    @State private var slots: [TeamSlot] = []
    @State private var singleAccount: UUID?
    @State private var savingName: String?
    @State private var directory: String?
    @FocusState private var nameFocused: Bool

    private var folderName: String? { directory.map { URL(fileURLWithPath: $0).lastPathComponent } }
    private var isNew: Bool { request.workspaceID == nil }
    private var existingCount: Int {
        cockpit.workspaces.workspaces.first { $0.id == request.workspaceID }?.panes.count ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isNew { folderSection }
                HStack(alignment: .top, spacing: 0) {
                    templateList
                        .frame(width: 200)
                    Rectangle().fill(Theme.bar).frame(width: 1)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: 400)
                footer
            }
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            singleAccount = accounts.accounts.first?.id
            directory = request.directory
            select(choice)
        }
    }

    // MARK: Partes

    private var header: some View {
        HStack(spacing: 8) {
            Text(isNew ? "Nova equipe" : "Adicionar equipe")
                .font(Theme.mono(13, .bold)).foregroundStyle(Theme.text)
            if let folderName { Text(folderName).font(Theme.mono(11)).foregroundStyle(Theme.dim) }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.bar).frame(height: 1) }
    }

    private var folderSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Pasta do projeto")
                if let directory, let folderName {
                    Text(folderName).font(Theme.mono(11.5, .bold)).foregroundStyle(Theme.text)
                    Text((directory as NSString).abbreviatingWithTildeInPath)
                        .font(Theme.mono(10)).foregroundStyle(Theme.faint)
                        .lineLimit(1).truncationMode(.middle)
                    if cockpit.workspace(at: directory) != nil {
                        Text("Já aberta como workspace. A equipe será adicionada a ele.")
                            .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                } else {
                    Text("Nenhuma pasta escolhida.").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
            Button(directory == nil ? "Selecionar pasta…" : "Trocar", action: chooseFolder)
                .buttonStyle(.duo(directory == nil ? .primary : .secondary))
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.bar).frame(height: 1) }
    }

    private var templateList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Equipes").padding(.horizontal, 10).padding(.vertical, 8)
                row(.single, title: "Um painel só", subtitle: "sem papéis")
                ForEach(teams.all) { template in
                    row(.template(template.id), title: template.name, subtitle: "\(template.slots.count) painéis",
                        removable: !teams.isBuiltIn(template.id))
                }
                row(.custom, title: "Personalizada", subtitle: "monte do zero")
            }
            .padding(6)
        }
    }

    private func row(_ value: Choice, title: String, subtitle: String, removable: Bool = false) -> some View {
        let active = choice == value
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.mono(11.5, .bold)).foregroundStyle(active ? Theme.text : Theme.soft)
                Text(subtitle).font(Theme.mono(10)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
            if removable, case .template(let id) = value {
                GlyphButton(glyph: "×", help: "Apagar template", size: 11) {
                    teams.remove(id)
                    if active { select(.template(TeamTemplate.standard.id)) }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.accent.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { select(value) }
    }

    @ViewBuilder
    private var detail: some View {
        if choice == .single {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Conta")
                accountPicker($singleAccount)
                Text("Abre um Claude Code comum, sem papel.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                counters
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.bar).frame(height: 1) }
                if slots.isEmpty {
                    Text("Adicione papéis com o +.")
                        .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        .padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(slots.enumerated()), id: \.element.id) { index, _ in
                                memberRow(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Spacer(minLength: 0)
                if slots.filter({ $0.role.isDev }).count >= 2 {
                    Text("Cada dev trabalha numa cópia isolada do repositório (git worktree) em .claude/worktrees/. O gerente junta as branches.")
                        .font(Theme.mono(10)).foregroundStyle(Theme.faint)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
        }
    }

    private var counters: some View {
        HStack(spacing: 12) {
            ForEach(TeamRole.allCases) { role in
                let n = slots.filter { $0.role == role }.count
                HStack(spacing: 6) {
                    Text(role.short).font(Theme.mono(10.5, .bold)).foregroundStyle(role.color)
                    CountStepper(value: n, tint: role.color, help: role.short,
                                 decrement: { removeLast(role) }, increment: { add(role) })
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func memberRow(_ index: Int) -> some View {
        let slot = slots[index]
        return HStack(spacing: 10) {
            Text("p\(existingCount + index + 1)")
                .font(Theme.mono(11)).foregroundStyle(Theme.faint).frame(width: 26, alignment: .leading)
            Text(slot.role.title)
                .font(Theme.mono(11.5, .bold)).foregroundStyle(slot.role.color)
                .frame(width: 88, alignment: .leading)
            accountPicker(Binding(get: { slots[index].accountID }, set: { slots[index].accountID = $0 }))
            SegmentedChoice(options: AIModel.allCases,
                            selection: Binding(get: { slots[index].model }, set: { slots[index].model = $0; edited() }),
                            label: { $0.rawValue }, tint: slot.role.color)
            SegmentedChoice(options: Effort.allCases,
                            selection: Binding(get: { slots[index].effort }, set: { slots[index].effort = $0; edited() }),
                            label: { $0.label }, tint: slot.role.color)
            Spacer(minLength: 0)
            GlyphButton(glyph: "×", help: "Remover", size: 11) {
                slots.remove(at: index)
                edited()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }

    private func accountPicker(_ binding: Binding<UUID?>) -> some View {
        DuoMenuPicker(options: accounts.accounts.map { .init(value: Optional($0.id), label: $0.name, color: $0.color) },
                      selection: binding, width: 110)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if choice != .single {
                if let name = savingName {
                    TextField("Nome do template", text: Binding(get: { name }, set: { savingName = $0 }))
                        .textFieldStyle(.plain)
                        .duoField(width: 180)
                        .focused($nameFocused)
                        .onSubmit(saveTemplate)
                    Button("Salvar", action: saveTemplate)
                        .buttonStyle(.duo(.secondary))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancelar") { savingName = nil }
                        .buttonStyle(.duo(.ghost))
                } else {
                    Button("Salvar como template") {
                        savingName = ""
                        nameFocused = true
                    }
                    .buttonStyle(.duo(.ghost))
                    .disabled(slots.isEmpty)
                }
            }
            Spacer()
            Button("Cancelar") { cockpit.teamSetup = nil }
                .buttonStyle(.duo(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle) {
                guard let directory else { return }
                if choice != .single { teams.remember(slots) }
                cockpit.finishTeamSetup(request, directory: directory,
                                        slots: choice == .single ? [] : slots, singleAccount: singleAccount)
            }
            .buttonStyle(.duo(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(directory == nil || (choice != .single && slots.isEmpty))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(Theme.bar).frame(height: 1) }
    }

    private var confirmTitle: String {
        let verb = directory.map { cockpit.workspace(at: $0) != nil } == true ? "Adicionar" : "Abrir"
        return choice == .single ? verb : "\(verb) equipe (\(slots.count))"
    }

    // MARK: Ações

    private func chooseFolder() {
        cockpit.chooseFolder { path in
            directory = path
        }
    }

    private func select(_ value: Choice) {
        choice = value
        savingName = nil
        switch value {
        case .single:
            slots = []
        case .custom:
            slots = []
        case .template(let id):
            let template = teams.all.first { $0.id == id } ?? TeamTemplate.standard
            slots = template.slots.map { slot in
                TeamSlot(role: slot.role, model: slot.model, effort: slot.effort, accountID: defaultAccount(for: slot.role))
            }
        }
    }

    private func defaultAccount(for role: TeamRole) -> UUID? {
        if let id = teams.lastAccount(for: role), accounts.account(id) != nil { return id }
        return accounts.accounts.first?.id
    }

    private func add(_ role: TeamRole) {
        // Mantém os papéis agrupados na ordem de TeamRole.
        let order = TeamRole.allCases
        let slot = TeamSlot(role: role, accountID: defaultAccount(for: role))
        let at = slots.lastIndex { order.firstIndex(of: $0.role)! <= order.firstIndex(of: role)! }.map { $0 + 1 } ?? 0
        slots.insert(slot, at: at)
        edited()
    }

    private func removeLast(_ role: TeamRole) {
        guard let i = slots.lastIndex(where: { $0.role == role }) else { return }
        slots.remove(at: i)
        edited()
    }

    /// Mexer na composição de um template vira equipe personalizada.
    private func edited() {
        if case .template = choice { choice = .custom }
    }

    private func saveTemplate() {
        guard let name = savingName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return }
        let template = teams.saveTemplate(name: name, slots: slots)
        savingName = nil
        choice = .template(template.id)
    }
}

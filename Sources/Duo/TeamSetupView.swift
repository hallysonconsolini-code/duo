import SwiftUI

/// Tela de nova equipe, na área central: escolher a pasta do projeto e um painel só, um template de equipe
/// ou uma equipe montada, com conta, modelo e esforço de cada membro. Pasta e equipe em
/// qualquer ordem. Ao adicionar equipe a um workspace existente, a pasta é a dele.
struct TeamSetupView: View {
    @EnvironmentObject var cockpit: Cockpit
    @EnvironmentObject var accounts: AccountStore
    @EnvironmentObject var teams: TeamStore
    @EnvironmentObject var roles: RoleStore
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
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pasta do projeto", subtitle: "onde a equipe vai trabalhar")
            HStack(spacing: 12) {
                Image(systemName: directory == nil ? "folder.badge.plus" : "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(directory == nil ? Theme.faint : Theme.soft)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    if let directory, let folderName {
                        Text(folderName).font(Theme.mono(11.5, .bold)).foregroundStyle(Theme.text)
                        Text((directory as NSString).abbreviatingWithTildeInPath)
                            .font(Theme.mono(10)).foregroundStyle(Theme.faint)
                            .lineLimit(1).truncationMode(.middle)
                        if cockpit.workspace(at: directory) != nil {
                            Text("Já aberta como workspace. A equipe será adicionada a ele.")
                                .font(Theme.mono(10)).foregroundStyle(Theme.yellow.opacity(0.8))
                        }
                    } else {
                        Text("Nenhuma pasta escolhida.").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }
                }
                Spacer(minLength: 0)
                Button(directory == nil ? "Selecionar pasta…" : "Trocar", action: chooseFolder)
                    .buttonStyle(.duo(directory == nil ? .primary : .secondary))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bar.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.paneBorder, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
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
                SectionHeader(title: "Conta", subtitle: "abre um Claude Code comum, sem papel")
                accountPicker($singleAccount)
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Composição", subtitle: "quantos membros de cada papel")
                    composition
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Membros", subtitle: "conta, modelo e esforço de cada painel") {
                        Text("\(slots.count) \(slots.count == 1 ? "painel" : "painéis")")
                            .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    }
                    members
                    if slots.filter({ roles.role($0.role).editsCode }).count >= 2 {
                        Text("Cada dev trabalha numa cópia isolada do repositório (git worktree) em .claude/worktrees/. O gerente junta as branches.")
                            .font(Theme.mono(10)).foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
    }

    private var composition: some View {
        // Cinco por linha na largura normal; papéis customizados quebram para a linha de baixo.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
            ForEach(roles.all) { role in
                RoleCard(role: role, count: slots.filter { $0.role == role.id }.count,
                         decrement: { removeLast(role.id) }, increment: { add(role) })
            }
        }
    }

    @ViewBuilder
    private var members: some View {
        if slots.isEmpty {
            Text("Nenhum membro. Adicione papéis com o + nos cards acima.")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.paneBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        } else {
            VStack(spacing: 0) {
                memberColumns
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, _ in
                    Rectangle().fill(Theme.paneBorder.opacity(0.6)).frame(height: 1)
                    memberRow(index)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bar.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.paneBorder, lineWidth: 1))
        }
    }

    private enum Column {
        static let pane: CGFloat = 24
        static let role: CGFloat = 104
        static let account: CGFloat = 104
        static let model: CGFloat = 144
        static let effort: CGFloat = 136
        static let spacing: CGFloat = 8
    }

    private var memberColumns: some View {
        HStack(spacing: Column.spacing) {
            columnTitle("", Column.pane)
            columnTitle("papel", Column.role)
            columnTitle("conta", Column.account)
            columnTitle("modelo", Column.model)
            columnTitle("esforço", Column.effort)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    private func columnTitle(_ text: String, _ width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(Theme.mono(9, .bold)).tracking(1.2).foregroundStyle(Theme.faint)
            .frame(width: width, alignment: .leading)
    }

    private func memberRow(_ index: Int) -> some View {
        let slot = slots[index]
        let role = roles.role(slot.role)
        return HStack(spacing: Column.spacing) {
            Text("p\(existingCount + index + 1)")
                .font(Theme.mono(11)).foregroundStyle(Theme.faint).frame(width: Column.pane, alignment: .leading)
            HStack(spacing: 6) {
                RoleIcon(role: role, size: 12)
                Text(role.title)
                    .font(Theme.mono(11.5, .bold)).foregroundStyle(role.color)
                    .lineLimit(1)
            }
            .frame(width: Column.role, alignment: .leading)
            accountPicker(Binding(get: { slots[index].accountID }, set: { slots[index].accountID = $0 }))
                .frame(width: Column.account, alignment: .leading)
            SegmentedChoice(options: AIModel.allCases,
                            selection: Binding(get: { slots[index].model }, set: { slots[index].model = $0; edited() }),
                            label: { $0.rawValue }, tint: role.color)
                .frame(width: Column.model, alignment: .leading)
            SegmentedChoice(options: Effort.allCases,
                            selection: Binding(get: { slots[index].effort }, set: { slots[index].effort = $0; edited() }),
                            label: { $0.label }, tint: role.color)
                .frame(width: Column.effort, alignment: .leading)
            Spacer(minLength: 0)
            GlyphButton(glyph: "×", help: "Remover", size: 11) {
                slots.remove(at: index)
                edited()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func accountPicker(_ binding: Binding<UUID?>) -> some View {
        DuoMenuPicker(options: accounts.accounts.map { .init(value: Optional($0.id), label: $0.name, color: $0.color) },
                      selection: binding, width: 104)
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
            // Papéis apagados (arquivados) ficam de fora ao aplicar o template.
            slots = template.slots.filter { roles.isAvailable($0.role) }.map { slot in
                TeamSlot(role: slot.role, model: slot.model, effort: slot.effort, accountID: defaultAccount(for: slot.role))
            }
        }
    }

    private func defaultAccount(for role: RoleID) -> UUID? {
        if let id = teams.lastAccount(for: role), accounts.account(id) != nil { return id }
        return accounts.accounts.first?.id
    }

    private func add(_ role: Role) {
        // Mantém os papéis agrupados na ordem do RoleStore.
        let slot = TeamSlot(role: role, accountID: defaultAccount(for: role.id))
        let at = slots.lastIndex { roles.order(of: $0.role) <= roles.order(of: role.id) }.map { $0 + 1 } ?? 0
        slots.insert(slot, at: at)
        edited()
    }

    private func removeLast(_ role: RoleID) {
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

// MARK: Card de papel

/// Card de um papel na composição da equipe: ícone, nome, o que faz, modelo padrão e o contador.
/// Apagado com 0 membros, aceso na cor do papel com 1 ou mais.
private struct RoleCard: View {
    let role: Role
    let count: Int
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        let lit = count > 0
        VStack(spacing: 6) {
            RoleIcon(role: role, size: 22, lit: lit)
                .padding(.top, 4)
                .padding(.bottom, 2)
            Text(role.title)
                .font(Theme.mono(11.5, .bold))
                .foregroundStyle(lit ? Theme.text : Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(role.blurb.isEmpty ? " " : role.blurb)
                .font(Theme.mono(10))
                .foregroundStyle(lit ? Theme.soft : Theme.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(role.defaultModel.rawValue) · \(role.defaultEffort.label)")
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
            Spacer(minLength: 0)
            CountStepper(value: count, tint: role.color, help: role.short,
                         decrement: decrement, increment: increment)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .background(RoundedRectangle(cornerRadius: 10).fill(lit ? role.color.opacity(0.07) : Theme.bar.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(lit ? role.color.opacity(0.4) : Theme.paneBorder, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: lit)
    }
}

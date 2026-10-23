import Foundation
import SwiftUI
import AppKit

// MARK: Identificador

/// Id estável de um papel. Gravado como texto puro ("manager", "seniorDev"...), o mesmo
/// formato do antigo enum TeamRole, então painéis e templates salvos continuam decodificando.
struct RoleID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue }

    static let manager: RoleID = "manager"
    static let seniorDev: RoleID = "seniorDev"
    static let juniorDev: RoleID = "juniorDev"
    static let designer: RoleID = "designer"
    static let qa: RoleID = "qa"

    static let builtIn: [RoleID] = [.manager, .seniorDev, .juniorDev, .designer, .qa]

    var isBuiltIn: Bool { Self.builtIn.contains(self) }
}

// MARK: Papel

/// Um papel da equipe: os 5 do Duo (editáveis, com "restaurar padrão") ou um criado pelo usuário.
struct Role: Codable, Identifiable, Equatable {
    var id: RoleID
    /// Nome curto, em minúsculas: chips, list_panes, lista da equipe ("dev sênior").
    var short: String
    /// Nome de exibição: cards e títulos ("Dev sênior").
    var title: String
    /// SF Symbol. Um nome que não existe cai em `person.fill` (ver `resolvedSymbol`).
    var symbol: String
    /// Selo opcional no canto do ícone (ex.: "SR", "JR").
    var badge: String?
    var colorHex: String
    var defaultModel: AIModel
    var defaultEffort: Effort
    /// Edita código: conta como dev para o worktree e recebe as linhas de branch/commit no prompt.
    var editsCode: Bool
    /// O que o papel faz, numa linha. O gerente vê isso para saber o que delegar.
    var blurb: String
    /// Texto do papel no system prompt. O Duo acrescenta por cima as partes automáticas
    /// (projeto, equipe, comunicação, de quem recebe tarefas, worktree, distribuição do gerente).
    var instructions: String
    /// Papel customizado apagado: some das listas, mas continua resolvendo para painéis e
    /// templates que ainda o usam.
    var archived = false

    var isBuiltIn: Bool { id.isBuiltIn }
    var color: Color { Color(hex: colorHex) }

    var resolvedSymbol: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : "person.fill"
    }

    init(id: RoleID, short: String, title: String, symbol: String, badge: String? = nil, colorHex: String,
         defaultModel: AIModel, defaultEffort: Effort, editsCode: Bool, blurb: String, instructions: String,
         archived: Bool = false) {
        self.id = id
        self.short = short
        self.title = title
        self.symbol = symbol
        self.badge = badge
        self.colorHex = colorHex
        self.defaultModel = defaultModel
        self.defaultEffort = defaultEffort
        self.editsCode = editsCode
        self.blurb = blurb
        self.instructions = instructions
        self.archived = archived
    }

    /// Tolerante a campos faltando, para o roles.json sobreviver a versões futuras/antigas.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(RoleID.self, forKey: .id)
        let fallback = Role.defaults(for: id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? fallback?.title ?? id.rawValue
        short = try c.decodeIfPresent(String.self, forKey: .short) ?? fallback?.short ?? title.lowercased()
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? fallback?.symbol ?? "person.fill"
        badge = try c.decodeIfPresent(String.self, forKey: .badge) ?? fallback?.badge
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? fallback?.colorHex ?? "#B6B7C0"
        defaultModel = (try? c.decodeIfPresent(AIModel.self, forKey: .defaultModel)) ?? fallback?.defaultModel ?? .sonnet
        defaultEffort = (try? c.decodeIfPresent(Effort.self, forKey: .defaultEffort)) ?? fallback?.defaultEffort ?? .medium
        editsCode = try c.decodeIfPresent(Bool.self, forKey: .editsCode) ?? fallback?.editsCode ?? false
        blurb = try c.decodeIfPresent(String.self, forKey: .blurb) ?? fallback?.blurb ?? ""
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? fallback?.instructions ?? ""
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    /// Papel que não existe mais no store (id desconhecido): mostra o id em cinza.
    static func placeholder(_ id: RoleID) -> Role {
        Role(id: id, short: id.rawValue, title: id.rawValue, symbol: "questionmark.circle", colorHex: "#6B7280",
             defaultModel: .sonnet, defaultEffort: .medium, editsCode: false, blurb: "", instructions: "")
    }
}

// MARK: Papéis do Duo

extension Role {
    static let manager = Role(
        id: .manager, short: "gerente", title: "Gerente", symbol: "list.bullet.clipboard", colorHex: "#FECACA",
        defaultModel: .opus, defaultEffort: .high, editsCode: false, blurb: "planeja e revisa",
        instructions: """
        Você é o GERENTE. O usuário conversa com você.
        - Não escreva nem edite código. Leia, planeje, distribua e revise.
        - Quebre o pedido em tarefas pequenas, cada uma com critério de pronto claro.
        - Tarefas independentes podem ir para colegas diferentes ao mesmo tempo: mande todas com send_to_pane e depois espere cada um com wait_for_pane.
        - Se um colega ficar esperando permissão do usuário, avise o usuário.
        - No fim, entregue ao usuário um resumo: o que foi feito, por quem, o que ficou pendente.
        """)

    static let seniorDev = Role(
        id: .seniorDev, short: "dev sênior", title: "Dev sênior", symbol: "chevron.left.forwardslash.chevron.right",
        badge: "SR", colorHex: "#34D399", defaultModel: .opus, defaultEffort: .high, editsCode: true,
        blurb: "código complexo",
        instructions: """
        Você é DEV SÊNIOR: arquitetura, bugs difíceis e partes críticas.
        - Faça só o que foi pedido.
        - Rode build e testes do que mudou, quando existirem.
        - Termine com: arquivos alterados, o que foi feito, se build/testes passaram, dúvidas ou riscos.
        """)

    static let juniorDev = Role(
        id: .juniorDev, short: "dev júnior", title: "Dev júnior", symbol: "chevron.left.forwardslash.chevron.right",
        badge: "JR", colorHex: "#86EFAC", defaultModel: .sonnet, defaultEffort: .medium, editsCode: true,
        blurb: "tarefas simples",
        instructions: """
        Você é DEV JÚNIOR: tarefas simples e mecânicas.
        - Faça só o que foi pedido.
        - Rode build e testes do que mudou, quando existirem.
        - Termine com: arquivos alterados, o que foi feito, se build/testes passaram, dúvidas ou riscos.
        """)

    static let designer = Role(
        id: .designer, short: "designer", title: "Designer", symbol: "paintpalette", colorHex: "#F472B6",
        defaultModel: .opus, defaultEffort: .medium, editsCode: false, blurb: "Figma e UI",
        instructions: """
        Você é o DESIGNER.
        - Use as ferramentas do Figma (servidor MCP do Figma) para criar e ler telas. Se não estiverem disponíveis, avise.
        - Não edite código do projeto.
        - Entregue specs que um dev consiga implementar: layout, componentes, espaçamentos, cores/tokens, estados (vazio, carregando, erro) e o link do frame.
        """)

    static let qa = Role(
        id: .qa, short: "qa", title: "QA", symbol: "checkmark.seal", colorHex: "#FACC15",
        defaultModel: .sonnet, defaultEffort: .low, editsCode: false, blurb: "testa entregas",
        instructions: """
        Você é o QA.
        - Não edite código de produção.
        - Teste o que for pedido na pasta/branch indicada: build, testes automatizados, lint e o comportamento descrito.
        - Responda: passou ou falhou; para cada bug, passos para reproduzir, resultado esperado x obtido e arquivo:linha provável.
        """)

    static let builtIn: [Role] = [manager, seniorDev, juniorDev, designer, qa]

    /// Versão original de um papel do Duo (o "restaurar padrão").
    static func defaults(for id: RoleID) -> Role? {
        builtIn.first { $0.id == id }
    }
}

// MARK: Store

/// Papéis disponíveis, gravados em roles.json: edições dos papéis do Duo + papéis customizados.
///
/// Apagar um papel customizado o arquiva em vez de removê-lo: ele some dos cards, do ⌘T e
/// dos templates aplicados, mas painéis que já o usam continuam com nome, cor e prompt.
@MainActor
final class RoleStore: ObservableObject {
    /// Papéis do Duo editados pelo usuário (só os editados).
    @Published private(set) var overrides: [RoleID: Role] = [:]
    /// Papéis criados pelo usuário, inclusive os arquivados.
    @Published private(set) var custom: [Role] = []

    private let file: URL

    private struct Stored: Codable {
        var overrides: [Role] = []
        var custom: [Role] = []
    }

    init(file: URL = Paths.appSupport.appendingPathComponent("roles.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            overrides = Dictionary(stored.overrides.filter(\.isBuiltIn).map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
            custom = stored.custom.filter { !$0.isBuiltIn }
        }
    }

    // MARK: Leitura

    /// Papéis para escolher: os 5 do Duo (com edições) e os customizados não apagados, nesta ordem.
    var all: [Role] {
        Role.builtIn.map { overrides[$0.id] ?? $0 } + custom.filter { !$0.archived }
    }

    /// Sempre devolve um papel: arquivado ou desconhecido vira um papel válido (placeholder).
    func role(_ id: RoleID) -> Role {
        if let edited = overrides[id] { return edited }
        if let builtIn = Role.defaults(for: id) { return builtIn }
        return custom.first { $0.id == id } ?? .placeholder(id)
    }

    /// Papel disponível para escolha (não arquivado e existente).
    func isAvailable(_ id: RoleID) -> Bool {
        all.contains { $0.id == id }
    }

    /// Um papel do Duo com alguma edição salva.
    func isEdited(_ id: RoleID) -> Bool { overrides[id] != nil }

    /// Ordem do papel em `all` (papéis fora da lista vão para o fim).
    func order(of id: RoleID) -> Int {
        all.firstIndex { $0.id == id } ?? Int.max
    }

    // MARK: Escrita

    /// Rascunho de papel novo, ainda fora do store. Salve com `create(_:)`.
    func draft() -> Role {
        Role(id: RoleID("custom-\(UUID().uuidString.lowercased())"), short: "novo papel", title: "Novo papel",
             symbol: "person.fill", colorHex: "#38BDF8", defaultModel: .sonnet, defaultEffort: .medium,
             editsCode: false, blurb: "", instructions: "")
    }

    /// Cria um papel customizado (um rascunho de `draft()`). Devolve o papel salvo.
    @discardableResult
    func create(_ role: Role) -> Role {
        var role = role
        if role.isBuiltIn || custom.contains(where: { $0.id == role.id }) {
            role.id = draft().id
        }
        role.archived = false
        custom.append(role)
        save()
        return role
    }

    /// Salva um papel editado. Papel do Duo vira edição (desfaça com `restore`).
    func update(_ role: Role) {
        if role.isBuiltIn {
            var role = role
            role.archived = false
            overrides[role.id] = role == Role.defaults(for: role.id) ? nil : role
        } else if let i = custom.firstIndex(where: { $0.id == role.id }) {
            custom[i] = role
        } else {
            return
        }
        save()
    }

    /// Volta um papel do Duo ao padrão.
    func restore(_ id: RoleID) {
        guard overrides.removeValue(forKey: id) != nil else { return }
        save()
    }

    /// Apaga um papel customizado (arquiva; ver a nota da classe). Papéis do Duo não são apagados.
    func delete(_ id: RoleID) {
        guard !id.isBuiltIn, let i = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[i].archived = true
        save()
    }

    private func save() {
        let stored = Stored(overrides: Role.builtIn.compactMap { overrides[$0.id] }, custom: custom)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(stored).write(to: file, options: .atomic)
        } catch {
            NSLog("Duo: falha ao salvar papéis: \(error)")
        }
    }
}

// MARK: Ícone

/// Ícone do papel na cor dele, com o selo (SR/JR...) no canto quando houver.
struct RoleIcon: View {
    let role: Role
    var size: CGFloat = 20
    var lit = true

    var body: some View {
        let color = lit ? role.color : role.color.opacity(0.35)
        Image(systemName: role.resolvedSymbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size * 1.5, height: size * 1.2)
            .overlay(alignment: .bottomTrailing) {
                if let badge = role.badge, !badge.isEmpty, size >= 16 {
                    Text(badge)
                        .font(Theme.mono(size * 0.38, .bold))
                        .foregroundStyle(Theme.bg)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(color))
                        .offset(x: size * 0.25, y: size * 0.25)
                }
            }
    }
}

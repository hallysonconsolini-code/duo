import Foundation
import SwiftUI

// MARK: Papéis, modelos e esforço

enum TeamRole: String, Codable, CaseIterable, Identifiable {
    case manager, seniorDev, juniorDev, designer, qa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manager: "Gerente"
        case .seniorDev: "Dev sênior"
        case .juniorDev: "Dev júnior"
        case .designer: "Designer"
        case .qa: "QA"
        }
    }

    var short: String {
        switch self {
        case .manager: "gerente"
        case .seniorDev: "dev sênior"
        case .juniorDev: "dev júnior"
        case .designer: "designer"
        case .qa: "qa"
        }
    }

    var defaultModel: AIModel {
        switch self {
        case .manager, .seniorDev, .designer: .opus
        case .juniorDev, .qa: .sonnet
        }
    }

    var defaultEffort: Effort {
        switch self {
        case .manager, .seniorDev: .high
        case .juniorDev, .designer: .medium
        case .qa: .low
        }
    }

    var isDev: Bool { self == .seniorDev || self == .juniorDev }

    var color: Color {
        switch self {
        case .manager: Theme.accentSoft
        case .seniorDev: Theme.green
        case .juniorDev: Color(hex: "#86EFAC")
        case .designer: Color(hex: "#F472B6")
        case .qa: Theme.yellow
        }
    }
}

/// Valor passado em `claude --model` (alias, sempre aponta para a versão mais nova).
enum AIModel: String, Codable, CaseIterable, Identifiable {
    case opus, sonnet, haiku
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Valor passado em `claude --effort`.
enum Effort: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: "baixo"
        case .medium: "médio"
        case .high: "alto"
        }
    }
}

// MARK: Templates

/// Um membro da equipe antes de virar painel.
struct TeamSlot: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: TeamRole
    var model: AIModel
    var effort: Effort
    /// Não vai para o template salvo: a conta vem da última escolha para o papel.
    var accountID: UUID?

    init(role: TeamRole, model: AIModel? = nil, effort: Effort? = nil, accountID: UUID? = nil) {
        self.role = role
        self.model = model ?? role.defaultModel
        self.effort = effort ?? role.defaultEffort
        self.accountID = accountID
    }
}

struct TeamTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var slots: [TeamSlot]

    static let standard = TeamTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!,
        name: "Equipe padrão",
        slots: [.init(role: .manager), .init(role: .seniorDev), .init(role: .juniorDev)]
    )

    static let large = TeamTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!,
        name: "Equipe grande",
        slots: [
            .init(role: .manager), .init(role: .seniorDev), .init(role: .juniorDev),
            .init(role: .juniorDev), .init(role: .designer), .init(role: .qa),
        ]
    )

    static let builtIn = [standard, large]

    var summary: String {
        TeamRole.allCases.compactMap { role in
            let n = slots.filter { $0.role == role }.count
            return n == 0 ? nil : (n == 1 ? role.short : "\(n) \(role.short)")
        }
        .joined(separator: " · ")
    }
}

@MainActor
final class TeamStore: ObservableObject {
    @Published var custom: [TeamTemplate] {
        didSet { save() }
    }

    private static let file = Paths.appSupport.appendingPathComponent("teams.json")
    private static let accountsKey = "teamRoleAccounts"

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let decoded = try? JSONDecoder().decode([TeamTemplate].self, from: data) {
            custom = decoded
        } else {
            custom = []
        }
    }

    var all: [TeamTemplate] { TeamTemplate.builtIn + custom }

    func isBuiltIn(_ id: UUID) -> Bool { TeamTemplate.builtIn.contains { $0.id == id } }

    func saveTemplate(name: String, slots: [TeamSlot]) -> TeamTemplate {
        let clean = slots.map { TeamSlot(role: $0.role, model: $0.model, effort: $0.effort) }
        let template = TeamTemplate(name: name, slots: clean)
        custom.append(template)
        return template
    }

    func remove(_ id: UUID) {
        custom.removeAll { $0.id == id }
    }

    /// Última conta escolhida para cada papel.
    func lastAccount(for role: TeamRole) -> UUID? {
        let map = UserDefaults.standard.dictionary(forKey: Self.accountsKey) as? [String: String] ?? [:]
        return map[role.rawValue].flatMap(UUID.init)
    }

    func remember(_ slots: [TeamSlot]) {
        var map = UserDefaults.standard.dictionary(forKey: Self.accountsKey) as? [String: String] ?? [:]
        for slot in slots {
            if let id = slot.accountID { map[slot.role.rawValue] = id.uuidString }
        }
        UserDefaults.standard.set(map, forKey: Self.accountsKey)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(custom).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("Duo: falha ao salvar templates: \(error)")
        }
    }
}

// MARK: Worktrees

/// Cópias isoladas do repositório para cada dev, em `.claude/worktrees/` do projeto.
/// Dentro da pasta do projeto, o Claude Code não pede para confiar na pasta de novo.
enum Worktrees {
    struct Result {
        let directory: String
        let branch: String
    }

    static func create(for directory: String, paneName: String) -> Result? {
        guard let top = git(["rev-parse", "--show-toplevel"], in: directory),
              git(["rev-parse", "--verify", "HEAD"], in: directory) != nil else { return nil }

        let root = URL(fileURLWithPath: top).appendingPathComponent(".claude/worktrees", isDirectory: true)
        let path = root.appendingPathComponent("duo-\(paneName)", isDirectory: true)
        // Mantém o mesmo subdiretório quando o workspace é uma pasta dentro do repositório.
        let rel = directory.hasPrefix(top + "/") ? String(directory.dropFirst(top.count + 1)) : ""
        func inside(_ base: URL) -> String { rel.isEmpty ? base.path : base.appendingPathComponent(rel).path }

        excludeFromGit(top)

        // Já existe (equipe montada de novo na mesma pasta): reaproveita.
        if FileManager.default.fileExists(atPath: path.path),
           let branch = git(["rev-parse", "--abbrev-ref", "HEAD"], in: path.path) {
            return Result(directory: inside(path), branch: branch)
        }

        var branch = "duo/\(paneName)"
        var n = 2
        while git(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: top) != nil {
            branch = "duo/\(paneName)-\(n)"
            n += 1
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard git(["worktree", "add", "-b", branch, path.path, "HEAD"], in: top) != nil else { return nil }
        return Result(directory: inside(path), branch: branch)
    }

    private static func excludeFromGit(_ top: String) {
        guard let common = git(["rev-parse", "--git-common-dir"], in: top) else { return }
        let gitDir = common.hasPrefix("/") ? common : top + "/" + common
        let exclude = URL(fileURLWithPath: gitDir).appendingPathComponent("info/exclude")
        let line = ".claude/worktrees/"
        let current = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
        guard !current.split(separator: "\n").contains(where: { $0 == line }) else { return }
        try? FileManager.default.createDirectory(at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = current.isEmpty || current.hasSuffix("\n") ? current + line + "\n" : current + "\n" + line + "\n"
        try? text.write(to: exclude, atomically: true, encoding: .utf8)
    }

    /// Roda git e devolve a saída (sem espaços nas pontas), ou nil se falhar.
    @discardableResult
    static func git(_ args: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Instruções de cada papel

/// Texto passado em `--append-system-prompt`: fica fixo mesmo depois de /clear ou compactação.
enum TeamPrompt {
    static func build(for me: PaneSpec, team: [PaneSpec], projectDir: String) -> String? {
        guard let role = me.role else { return nil }
        let home = NSHomeDirectory()
        func path(_ p: String) -> String { p.replacingOccurrences(of: home, with: "~") }

        let roster = team.map { pane -> String in
            var line = "- \(pane.name): \(pane.role?.short ?? "claude")"
            if let model = pane.model { line += " (\(model))" }
            if let branch = pane.branch { line += " · pasta \(path(pane.directory)) · branch \(branch)" }
            if pane.id == me.id { line += "  ← você" }
            return line
        }
        .joined(separator: "\n")

        let managers = team.filter { $0.role == .manager }
        let lead = managers.first
        let boss = lead.map { "o gerente (\($0.name))" } ?? "o usuário"
        let has: (TeamRole) -> Bool = { r in team.contains { $0.role == r } }
        let names: (TeamRole) -> String = { r in team.filter { $0.role == r }.map(\.name).joined(separator: ", ") }
        let usesWorktrees = team.contains { $0.branch != nil }

        var text = """
        # Equipe Duo
        Você faz parte de uma equipe de Claude Code no app Duo, trabalhando no projeto \(path(projectDir)).
        Equipe:
        \(roster)

        Comunicação: use as ferramentas do servidor MCP "duo". send_to_pane manda uma mensagem para um colega, \
        wait_for_pane espera ele terminar e devolve a resposta final, read_pane lê a última resposta, list_panes \
        mostra o estado de todos. Mensagens de colegas chegam começando com [mensagem de pN].
        Quando um colega te passa uma tarefa, ele lê a sua resposta final com wait_for_pane: não precisa mandar \
        mensagem de volta, apenas termine com um resumo objetivo.

        """

        switch role {
        case .manager:
            var lines = [
                "Você é o GERENTE\(me.id == lead?.id ? "" : " (gerente principal: \(lead?.name ?? "-"))"). O usuário conversa com você.",
                "- Não escreva nem edite código. Leia, planeje, distribua e revise.",
                "- Quebre o pedido em tarefas pequenas, cada uma com critério de pronto claro.",
            ]
            if has(.seniorDev) && has(.juniorDev) {
                lines.append("- Distribua por dificuldade: tarefas complexas (arquitetura, bugs difíceis, partes críticas) para o dev sênior (\(names(.seniorDev))); tarefas simples e mecânicas para o dev júnior (\(names(.juniorDev))). Isso economiza uso.")
            } else if has(.seniorDev) || has(.juniorDev) {
                lines.append("- Devs: \([names(.seniorDev), names(.juniorDev)].filter { !$0.isEmpty }.joined(separator: ", ")).")
            }
            if has(.designer) {
                lines.append("- Quando a tarefa tiver interface, peça antes ao designer (\(names(.designer))) as telas e specs no Figma, e repasse aos devs.")
            }
            if has(.qa) {
                lines.append("- Depois de cada entrega, peça ao QA (\(names(.qa))) para testar, indicando a pasta/branch. Bugs voltam para o dev responsável.")
            }
            lines.append("- Tarefas independentes podem ir para devs diferentes ao mesmo tempo: mande todas com send_to_pane e depois espere cada um com wait_for_pane.")
            if usesWorktrees {
                lines.append("- Cada dev trabalha na própria cópia do repositório (git worktree) e faz commit na própria branch. Revise com git -C <pasta do dev> diff/log. Quando aprovado, junte com git merge da branch do dev na pasta do projeto (você pode rodar git, só não escreve código). Em conflito, peça ao dev para atualizar a branch dele (git merge do branch principal) e resolver.")
            }
            lines.append("- Se um colega ficar esperando permissão do usuário, avise o usuário.")
            lines.append("- No fim, entregue ao usuário um resumo: o que foi feito, por quem, o que ficou pendente.")
            text += lines.joined(separator: "\n")

        case .seniorDev, .juniorDev:
            var lines = [
                "Você é \(role == .seniorDev ? "DEV SÊNIOR" : "DEV JÚNIOR"). Tarefas chegam de \(boss).",
                "- Faça só o que foi pedido. Se algo estiver ambíguo, pergunte a \(boss) e pare\(lead == nil ? "" : " (send_to_pane)").",
            ]
            if let branch = me.branch {
                lines.append("- Você trabalha na sua cópia isolada do repositório (git worktree) em \(path(me.directory)), branch \(branch). Edite só arquivos dentro dela.")
                lines.append("- Ao terminar cada tarefa, faça commit na sua branch com uma mensagem clara.")
            } else if team.filter({ $0.role?.isDev == true }).count > 1 {
                lines.append("- Outros devs editam a mesma pasta: mexa só nos arquivos da sua tarefa.")
            }
            lines.append("- Rode build e testes do que mudou, quando existirem.")
            lines.append("- Termine com: arquivos alterados, o que foi feito, se build/testes passaram, dúvidas ou riscos.")
            text += lines.joined(separator: "\n")

        case .designer:
            text += """
            Você é o DESIGNER. Tarefas chegam de \(boss).
            - Use as ferramentas do Figma (servidor MCP do Figma) para criar e ler telas. Se não estiverem disponíveis, avise.
            - Não edite código do projeto.
            - Entregue specs que um dev consiga implementar: layout, componentes, espaçamentos, cores/tokens, estados (vazio, carregando, erro) e o link do frame.
            """

        case .qa:
            text += """
            Você é o QA. Tarefas chegam de \(boss).
            - Não edite código de produção.
            - Teste o que for pedido na pasta/branch indicada: build, testes automatizados, lint e o comportamento descrito.
            - Responda: passou ou falhou; para cada bug, passos para reproduzir, resultado esperado x obtido e arquivo:linha provável.
            """
        }
        return text
    }
}

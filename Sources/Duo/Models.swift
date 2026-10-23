import Foundation
import SwiftUI
import AppKit

enum Paths {
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Duo", isDirectory: true)
    }()

    static let accounts = appSupport.appendingPathComponent("Accounts", isDirectory: true)
    static let accountsFile = appSupport.appendingPathComponent("accounts.json")
    static let workspacesFile = appSupport.appendingPathComponent("workspaces.json")
    /// Arquivos gerados por painel (config MCP e hooks), recriados a cada início.
    static let run = appSupport.appendingPathComponent("run", isDirectory: true)
    static let defaultClaudeConfig = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
}

/// Uma conta do Claude. Cada uma tem seu próprio login no Claude Code (via CLAUDE_CONFIG_DIR)
/// e seu próprio armazenamento de cookies no claude.ai (WKWebsiteDataStore isolado).
struct Account: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: String
    /// true = usa o ~/.claude padrão (o login que o Claude Code já tem nesta máquina).
    /// false = usa um diretório de configuração isolado, com login próprio.
    var usesDefaultClaudeConfig: Bool
    var webStoreID = UUID()

    var claudeConfigDir: URL? {
        usesDefaultClaudeConfig ? nil : Paths.accounts
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("claude", isDirectory: true)
    }

    var effectiveConfigDir: URL { claudeConfigDir ?? Paths.defaultClaudeConfig }

    var color: Color { Color(hex: colorHex) }
    var nsColor: NSColor { NSColor(hex: colorHex) }

    static let palette = ["#F59E0B", "#0EA5E9", "#A78BFA", "#34D399", "#F472B6", "#FB923C"]
}

@MainActor
final class AccountStore: ObservableObject {
    @Published var accounts: [Account] {
        didSet { save() }
    }

    init() {
        if let data = try? Data(contentsOf: Paths.accountsFile),
           let decoded = try? JSONDecoder().decode([Account].self, from: data),
           !decoded.isEmpty {
            accounts = decoded
        } else {
            accounts = [
                Account(name: "Conta 1", colorHex: Account.palette[0], usesDefaultClaudeConfig: true),
                Account(name: "Conta 2", colorHex: Account.palette[1], usesDefaultClaudeConfig: false),
            ]
            save()
        }
    }

    func account(_ id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    func update(_ account: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }), accounts[i] != account else { return }
        accounts[i] = account
    }

    func addAccount() {
        let color = Account.palette[accounts.count % Account.palette.count]
        accounts.append(Account(name: "Conta \(accounts.count + 1)", colorHex: color, usesDefaultClaudeConfig: false))
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Paths.appSupport, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(accounts).write(to: Paths.accountsFile, options: .atomic)
        } catch {
            NSLog("Duo: falha ao salvar contas: \(error)")
        }
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

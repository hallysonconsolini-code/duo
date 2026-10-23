import AppKit
import SwiftTerm

enum PaneStatus {
    case starting, idle, working, attention, exited

    var label: String {
        switch self {
        case .starting: "iniciando"
        case .idle: "pronto"
        case .working: "trabalhando"
        case .attention: "aguardando você"
        case .exited: "encerrado"
        }
    }
}

/// Endereço do servidor local que os painéis usam para MCP e hooks.
struct BridgeInfo {
    let port: UInt16
    let token: String
}

/// Um Claude Code rodando num painel, com a configuração de uma conta e ligado à ponte do app.
@MainActor
final class TerminalSession: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    let paneID: UUID
    let directory: String
    private let account: Account
    private let bridge: BridgeInfo
    private var initialPrompt: String?

    /// Recriada a cada reinício, para começar com a tela limpa.
    @Published private(set) var view: LocalProcessTerminalView
    @Published private(set) var title = ""
    @Published var status: PaneStatus = .starting

    var sessionID: String?
    var transcriptPath: String?
    /// Texto enviado por outro painel que ainda não terminou de ser respondido.
    var injectedSinceStop = false

    init(pane: PaneSpec, account: Account, bridge: BridgeInfo, initialPrompt: String?) {
        self.paneID = pane.id
        self.directory = pane.directory
        self.account = account
        self.bridge = bridge
        self.initialPrompt = initialPrompt
        self.sessionID = pane.resumableSessionID
        self.transcriptPath = pane.claudeTranscriptPath
        self.view = Self.makeView()
        super.init()
        start(resume: sessionID)
    }

    private static func makeView() -> LocalProcessTerminalView {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.font = NSFont(name: "SF Mono", size: 12)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = Theme.nsBg
        view.nativeForegroundColor = Theme.nsText
        view.caretColor = NSColor(hex: "#EF4444")
        view.optionAsMetaKey = false
        view.optionAsMetaKeyForFunctionalKeys = true
        return view
    }

    private var runDir: URL { Paths.run.appendingPathComponent(paneID.uuidString, isDirectory: true) }

    /// Config MCP (servidor "duo") e hooks que avisam o app do estado do painel.
    private func writeLaunchFiles() throws -> (mcp: URL, settings: URL) {
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        let base = "http://127.0.0.1:\(bridge.port)"
        let mcp: [String: Any] = [
            "mcpServers": [
                "duo": [
                    "type": "http",
                    "url": "\(base)/mcp",
                    "headers": ["Authorization": "Bearer \(bridge.token)", "X-Duo-Pane": paneID.uuidString],
                ],
            ],
        ]
        func hook(_ event: String) -> [String: Any] {
            let command = "curl -s -m 3 -X POST -H 'Authorization: Bearer \(bridge.token)' "
                + "-H 'X-Duo-Pane: \(paneID.uuidString)' -H 'Content-Type: application/json' "
                + "--data-binary @- '\(base)/hook/\(event)' >/dev/null 2>&1 || true"
            return ["matcher": "*", "hooks": [["type": "command", "command": command]]]
        }
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Stop", "Notification", "SessionEnd"]
        let settings: [String: Any] = [
            "hooks": Dictionary(uniqueKeysWithValues: events.map { ($0, [hook($0)]) }),
            "permissions": ["allow": ["mcp__duo"]],
        ]
        let mcpURL = runDir.appendingPathComponent("mcp.json")
        let settingsURL = runDir.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: mcp, options: .prettyPrinted).write(to: mcpURL)
        try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted).write(to: settingsURL)
        return (mcpURL, settingsURL)
    }

    private func start(resume: String?) {
        var env = ProcessInfo.processInfo.environment
        // Não herdar variáveis de outra sessão do Claude Code ou de outro terminal.
        for key in env.keys where key.hasPrefix("CLAUDE") {
            env.removeValue(forKey: key)
        }
        for key in ["TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ITERM_SESSION_ID", "__CFBundleIdentifier"] {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["DUO_ACCOUNT"] = account.name
        env["DUO_PANE"] = paneID.uuidString
        if let configDir = account.claudeConfigDir {
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            env["CLAUDE_CONFIG_DIR"] = configDir.path
        }

        var claude = "claude"
        if let files = try? writeLaunchFiles() {
            claude += " --mcp-config \(Self.quote(files.mcp.path)) --settings \(Self.quote(files.settings.path))"
        }
        let script: String
        if let resume {
            // Se a sessão não existir mais, abre uma nova.
            script = "\(claude) --resume \(Self.quote(resume)) || \(claude)"
        } else if let prompt = initialPrompt {
            script = "\(claude) \(Self.quote(prompt))"
        } else {
            script = claude
        }
        initialPrompt = nil

        let shell = env["SHELL"] ?? "/bin/zsh"
        view.processDelegate = self
        // Shell de login interativo carrega o PATH do usuário (nvm, brew...). Quando o
        // Claude Code sai, o painel continua num shell com o mesmo ambiente da conta.
        view.startProcess(
            executable: shell,
            args: ["-l", "-i", "-c", "\(script); exec \"$SHELL\" -l -i"],
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: nil,
            currentDirectory: directory
        )
        status = .starting
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Reinicia o Claude Code. Com `resume`, continua a mesma conversa.
    func restart(resume: Bool) {
        let old = view
        old.processDelegate = nil
        old.terminate()
        title = ""
        let resumeID = resume && transcriptPath.map(FileManager.default.fileExists(atPath:)) == true ? sessionID : nil
        if resumeID == nil { sessionID = nil }
        view = Self.makeView()
        start(resume: resumeID)
    }

    func terminate() {
        view.processDelegate = nil
        view.terminate()
        status = .exited
        try? FileManager.default.removeItem(at: runDir)
    }

    /// Digita um texto no Claude Code como colagem (preserva quebras de linha) e envia.
    func inject(_ text: String, submit: Bool = true) {
        let paste = "\u{1B}[200~" + text + "\u{1B}[201~"
        view.send(data: ArraySlice(Array(paste.utf8)))
        injectedSinceStop = true
        if submit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.view.send(data: ArraySlice(Array("\r".utf8)))
            }
        }
    }

    /// Últimas linhas visíveis do terminal.
    func screenText(lines: Int) -> String {
        let text = String(data: view.getBufferAsData(), encoding: .utf8) ?? ""
        var rows = text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while rows.last?.isEmpty == true { rows.removeLast() }
        return rows.suffix(lines).joined(separator: "\n")
    }

    /// Texto da última resposta do Claude, lido do transcript da sessão.
    func lastReply() -> String? {
        guard let transcriptPath,
              let data = FileManager.default.contents(atPath: transcriptPath),
              let content = String(data: data, encoding: .utf8) else { return nil }
        for line in content.split(separator: "\n").reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            let texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        return nil
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard source === view else { return }
        self.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard source === view else { return }
        status = .exited
        view.feed(text: "\r\n\u{1B}[2m[processo encerrado — use ↻ para reiniciar]\u{1B}[0m\r\n")
    }
}

import AppKit

/// Procura versões novas nas releases públicas do GitHub (API sem login, URLSession), baixa o
/// DMG e substitui o app instalado. Se a API pública não responder (404 com o repositório
/// privado, rede ou limite de taxa) e o `gh` estiver instalado e logado, usa o `gh`.
///
/// A verificação automática roda uma vez, 3s depois de abrir o app (AppDelegate); fora isso só
/// a pedido, em "Procurar atualizações…". A API sem login permite 60 consultas por hora por IP.
@MainActor
final class Updater: ObservableObject {
    static let repo = "hallysonconsolini-code/duo"

    struct Release {
        let tag: String
        let version: String
        let notes: String
        /// Link do DMG na API pública; nil quando a release veio do `gh`.
        var dmgURL: URL?
    }

    @Published private(set) var available: Release?
    @Published private(set) var isBusy = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Chamado ao clicar em "Encerrar" no fluxo de atualização, para não pedir confirmação de novo.
    var onWillRelaunch: (() -> Void)?

    // MARK: Checagem

    /// `interactive` mostra alertas também quando não há novidade ou dá erro.
    func check(interactive: Bool) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let release = try await fetchLatest()
                if Self.isNewer(release.version, than: Self.currentVersion) {
                    available = release
                    if interactive { promptToUpdate(release) }
                } else {
                    available = nil
                    if interactive { info("Você já está na versão mais recente (\(Self.currentVersion)).") }
                }
            } catch {
                if interactive { info("Não consegui procurar atualizações.", detail: error.localizedDescription) }
            }
        }
    }

    func promptToUpdate(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Duo \(release.version) disponível"
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = "Você está na \(Self.currentVersion).\n\n"
            + (notes.isEmpty ? "" : notes + "\n\n")
            + "O Duo vai fechar e reabrir. Os painéis retomam as conversas."
        alert.addButton(withTitle: "Atualizar")
        alert.addButton(withTitle: "Depois")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(release)
    }

    /// API pública primeiro; se falhar e houver `gh`, o caminho com o `gh`.
    private func fetchLatest() async throws -> Release {
        do {
            return try await Self.fetchPublic()
        } catch let publicError {
            guard Self.ghPath != nil else { throw Self.noGhError(after: publicError) }
            return try await Self.fetchWithGh()
        }
    }

    private static func fetchPublic() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Duo", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPFailure(status: status) }
        return try parse(data)
    }

    private static func fetchWithGh() async throws -> Release {
        try parse(try await gh(["api", "repos/\(repo)/releases/latest"]))
    }

    private static func parse(_ data: Data) throws -> Release {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw UpdateError("Resposta inesperada do GitHub.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        return Release(tag: tag, version: version, notes: json["body"] as? String ?? "", dmgURL: dmg)
    }

    /// Resposta HTTP que não é 200 da API pública (404 = repositório privado).
    private struct HTTPFailure: Error { let status: Int }

    /// Mensagem para quando a API pública falhou e não há `gh` para tentar.
    private static func noGhError(after error: Error) -> UpdateError {
        if let http = error as? HTTPFailure {
            switch http.status {
            case 404: return UpdateError("Não encontrei a versão mais recente do Duo. O repositório não está público e o GitHub CLI (gh) não está instalado.")
            case 403, 429: return UpdateError("O GitHub limitou as consultas por agora. Tente de novo daqui a uma hora.")
            default: return UpdateError("O GitHub respondeu com erro \(http.status). Tente de novo mais tarde.")
            }
        }
        if error is URLError { return UpdateError("Sem conexão com o GitHub. Confira a internet e tente de novo.") }
        return UpdateError(error.localizedDescription)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Instalação

    private func install(_ release: Release) {
        isBusy = true
        Task {
            do {
                let staged = try await download(release)
                try relaunch(replacingWith: staged)
            } catch {
                isBusy = false
                info("A atualização falhou.", detail: error.localizedDescription)
            }
        }
    }

    /// Baixa o DMG da release e extrai o Duo.app para uma pasta temporária.
    private func download(_ release: Release) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("duo-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        if let url = release.dmgURL {
            do {
                try await Self.downloadPublic(url, to: work)
            } catch {
                guard Self.ghPath != nil else { throw Self.noGhError(after: error) }
                try await Self.downloadWithGh(release, to: work)
            }
        } else {
            try await Self.downloadWithGh(release, to: work)
        }
        guard let dmg = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "dmg" }) else {
            throw UpdateError("A release \(release.tag) não tem DMG.")
        }

        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        _ = try await Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path])
        defer { Task { _ = try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) } }

        let staged = work.appendingPathComponent("Duo.app")
        _ = try await Self.run("/usr/bin/ditto", [mount.appendingPathComponent("Duo.app").path, staged.path])
        let bundleID = Bundle(url: staged)?.bundleIdentifier
        guard bundleID == Bundle.main.bundleIdentifier else {
            throw UpdateError("O DMG baixado não contém o Duo.")
        }
        return staged
    }

    private static func downloadPublic(_ url: URL, to work: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("Duo", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await URLSession.shared.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPFailure(status: status) }
        let name = url.lastPathComponent.hasSuffix(".dmg") ? url.lastPathComponent : "Duo.dmg"
        try FileManager.default.moveItem(at: file, to: work.appendingPathComponent(name))
    }

    private static func downloadWithGh(_ release: Release, to work: URL) async throws {
        _ = try await gh(["release", "download", release.tag, "-R", repo, "-p", "*.dmg", "-D", work.path, "--clobber"])
    }

    /// Um script em segundo plano espera o app fechar, troca o bundle e abre a versão nova.
    private func relaunch(replacingWith staged: URL) throws {
        let target = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        rm -rf "\(target).old"
        mv "\(target)" "\(target).old" && /usr/bin/ditto "\(staged.path)" "\(target)" && rm -rf "\(target).old" || mv "\(target).old" "\(target)"
        open "\(target)"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        try process.run()

        onWillRelaunch?()
        NSApp.terminate(nil)
    }

    // MARK: Processos

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private static let ghPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func gh(_ args: [String]) async throws -> Data {
        guard let ghPath else {
            throw UpdateError("O GitHub CLI (gh) não está instalado. Instale com: brew install gh && gh auth login")
        }
        return try await run(ghPath, args)
    }

    private static func run(_ executable: String, _ args: [String]) async throws -> Data {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw UpdateError(message.isEmpty ? "\(executable) falhou (\(process.terminationStatus))." : message)
            }
            return data
        }.value
    }

    private func info(_ message: String, detail: String? = nil) {
        let alert = NSAlert()
        alert.messageText = message
        if let detail { alert.informativeText = detail }
        alert.runModal()
    }
}

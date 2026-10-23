import SwiftUI
import AppKit
import UserNotifications

/// Preferências dos avisos (UserDefaults, as mesmas chaves do @AppStorage dos Ajustes).
enum NoticePrefs {
    /// Aviso no app a cada painel que termina.
    static let enabledKey = "notifyOnFinish"
    /// Notificação do macOS, com o Duo em segundo plano, quando a equipe de um workspace termina.
    static let backgroundKey = "notifyInBackground"
    /// Som baixo quando a equipe de um workspace termina.
    static let soundKey = "soundOnTeamDone"
    /// Id do som da equipe (`TeamSound.id`) e o volume dele (0 a 1).
    static let soundChoiceKey = "teamDoneSound"
    static let volumeKey = "teamDoneVolume"
    static let defaultVolume = 0.3

    static var enabled: Bool { flag(enabledKey) }
    static var background: Bool { flag(backgroundKey) }
    static var sound: Bool { flag(soundKey) }
    static var soundChoice: String { UserDefaults.standard.string(forKey: soundChoiceKey) ?? TeamSound.defaultID }
    static var volume: Double { UserDefaults.standard.object(forKey: volumeKey) as? Double ?? defaultVolume }

    private static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Sons para "equipe terminou": os MP3 em Resources/Sounds (copiados para o bundle pelo
/// build-app.sh) e o Pop do sistema, que é também o reserva se o arquivo não carregar.
struct TeamSound: Identifiable {
    let id: String
    let label: String

    static let popID = "pop"
    static let defaultID = "soft-electronic"

    static let all: [TeamSound] = [
        .init(id: "soft-electronic", label: "Eletrônico suave"),
        .init(id: "minimal-ai", label: "Minimal"),
        .init(id: "subtle-ai-1", label: "Sutil 1"),
        .init(id: "subtle-ai-2", label: "Sutil 2"),
        .init(id: "gentle-machine", label: "Máquina suave"),
        .init(id: "gentle-robot", label: "Robô gentil"),
        .init(id: "cute-robot", label: "Robô fofo"),
        .init(id: "tiny-robot", label: "Robô pequeno"),
        .init(id: "tiny-friendly", label: "Pequeno amigável"),
        .init(id: "futuristic", label: "Futurista"),
        .init(id: "ai-assistant-1", label: "Assistente 1"),
        .init(id: "ai-assistant-2", label: "Assistente 2"),
        .init(id: popID, label: "Pop (sistema)"),
    ]

    /// O som já carregado, ou o Pop se o id não existe ou o arquivo não abre.
    static func load(_ id: String) -> NSSound? {
        if id != popID,
           let url = Bundle.main.url(forResource: id, withExtension: "mp3", subdirectory: "Sounds"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            return sound
        }
        return NSSound(named: "Pop")
    }
}

/// Um aviso pequeno no canto da área de conteúdo.
struct Notice: Identifiable, Equatable {
    let id = UUID()
    let paneID: UUID
    let paneName: String
    let detail: String
    let colorHex: String
    /// Nome do workspace quando o painel é de outro workspace.
    let workspaceName: String?
}

/// Avisos de "painel terminou": no app (canto da tela, somem sozinhos) e, com o Duo em
/// segundo plano, notificação do macOS sem som.
@MainActor
final class Notices: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var items: [Notice] = []

    /// Chamado ao clicar num aviso (do app ou do macOS): foca o painel.
    var onOpen: ((UUID) -> Void)?

    private static let lifetime: TimeInterval = 4
    private static let maxVisible = 3

    /// Notificações do macOS só funcionam rodando de dentro de um .app com bundle id
    /// (com `swift run` o UNUserNotificationCenter derruba o processo).
    private let canUseSystem = Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    private var asked = false

    override init() {
        super.init()
        if canUseSystem { UNUserNotificationCenter.current().delegate = self }
    }

    // MARK: No app

    func show(_ notice: Notice) {
        // O mesmo painel de novo só substitui o aviso anterior.
        items.removeAll { $0.paneID == notice.paneID }
        items.append(notice)
        if items.count > Self.maxVisible { items.removeFirst(items.count - Self.maxVisible) }
        let id = notice.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { [weak self] in
            self?.dismiss(id)
        }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func open(_ notice: Notice) {
        dismiss(notice.id)
        onOpen?(notice.paneID)
    }

    // MARK: Som

    /// O som tocando agora. Fica guardado: um NSSound solto para de tocar ao ser liberado.
    private var current: NSSound?
    private var lastSound = Date.distantPast
    private static let soundGap: TimeInterval = 3

    /// Toca o som de "equipe terminou" escolhido, no máximo um a cada 3s no app todo.
    func playDone() {
        guard Date().timeIntervalSince(lastSound) >= Self.soundGap else { return }
        lastSound = Date()
        play(NoticePrefs.soundChoice, volume: NoticePrefs.volume)
    }

    /// Toca um som já, sem o intervalo mínimo (prévia dos Ajustes).
    func play(_ id: String, volume: Double) {
        current?.stop()
        guard let sound = TeamSound.load(id) else { return }
        sound.volume = Float(volume)
        current = sound
        sound.play()
    }

    // MARK: macOS

    /// Pede permissão uma vez (na primeira notificação ou ao ligar a opção nos Ajustes).
    func requestAuthorization() {
        guard canUseSystem, !asked else { return }
        asked = true
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) }
            catch { NSLog("Duo: notificações não autorizadas: \(error)") }
        }
    }

    /// `key` identifica a notificação: uma nova com a mesma chave substitui a anterior.
    func postSystem(title: String, body: String, paneID: UUID, key: String) {
        guard canUseSystem else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.userInfo = ["pane": paneID.uuidString]
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined:
                // Primeira vez que vai avisar: pede permissão agora, sem alarde.
                self.asked = true
                guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            case .authorized, .provisional:
                break
            default:
                return
            }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["pane"] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            if let raw, let id = UUID(uuidString: raw) { self.onOpen?(id) }
        }
    }

    /// Com o Duo na frente não mostra a notificação do macOS (o aviso do app já aparece).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}

// MARK: Vista

/// Pilha de avisos no canto inferior direito da área de conteúdo. Não pega foco: clicar foca o painel.
struct NoticeStack: View {
    @ObservedObject var notices: Notices

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(notices.items) { notice in
                NoticeToast(notice: notice) { notices.open(notice) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .animation(.easeOut(duration: 0.2), value: notices.items)
    }
}

private struct NoticeToast: View {
    let notice: Notice
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let color = Color(hex: notice.colorHex)
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(notice.paneName).font(Theme.mono(11, .bold)).foregroundStyle(Theme.text)
            if !notice.detail.isEmpty {
                Text(notice.detail).font(Theme.mono(11)).foregroundStyle(color)
            }
            Text("terminou").font(Theme.mono(11)).foregroundStyle(Theme.soft)
            if let ws = notice.workspaceName {
                Text("· \(ws)").font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.bar : Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hover ? color.opacity(0.5) : Theme.paneBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
        .help("Ir para \(notice.paneName)")
    }
}

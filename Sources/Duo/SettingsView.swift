import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettings()
                .tabItem { Label("Contas", systemImage: "person.2") }
            NoticeSettings()
                .tabItem { Label("Avisos", systemImage: "bell") }
        }
    }
}

/// Avisos de painel e de equipe terminando.
private struct NoticeSettings: View {
    @EnvironmentObject var cockpit: Cockpit
    @AppStorage(NoticePrefs.enabledKey) private var enabled = true
    @AppStorage(NoticePrefs.soundKey) private var sound = true
    @AppStorage(NoticePrefs.backgroundKey) private var background = true
    @AppStorage(NoticePrefs.soundChoiceKey) private var soundChoice = TeamSound.defaultID
    @AppStorage(NoticePrefs.volumeKey) private var volume = NoticePrefs.defaultVolume
    @AppStorage(NoticePrefs.soundOnlyInBackgroundKey) private var onlyInBackground = true

    private var soundControls: some View {
        HStack(spacing: 12) {
            Text("SOM").font(Theme.mono(9, .bold)).tracking(1.2).foregroundStyle(Theme.faint)
            DuoMenuPicker(options: TeamSound.all.map { .init(value: $0.id, label: $0.label) },
                          selection: Binding(get: { soundChoice }, set: {
                              soundChoice = $0
                              cockpit.notices.play($0, volume: volume)
                          }), width: 160)
            Button("▶") { cockpit.notices.play(soundChoice, volume: volume) }
                .buttonStyle(.duo(.secondary))
                .help("Ouvir")
            Text("VOLUME").font(Theme.mono(9, .bold)).tracking(1.2).foregroundStyle(Theme.faint)
                .padding(.leading, 8)
            SegmentedChoice(options: [0.3, 0.6, 1.0], selection: Binding(get: { Self.nearest(volume) }, set: {
                volume = $0
                cockpit.notices.play(soundChoice, volume: $0)
            }), label: { $0 == 0.3 ? "baixo" : $0 == 0.6 ? "médio" : "alto" })
        }
        .padding(.leading, 36)
        .disabled(!sound)
        .opacity(sound ? 1 : 0.4)
    }

    /// O nível mais próximo do volume salvo, para o seletor marcar um deles.
    private static func nearest(_ value: Double) -> Double {
        [0.3, 0.6, 1.0].min { abs($0 - value) < abs($1 - value) } ?? 0.3
    }

    private static let teamRule = "quando o gerente encerra o turno ou, sem gerente, quando todos os painéis param"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DuoToggle(isOn: $enabled, title: "Avisar quando um painel terminar",
                      detail: "Um aviso discreto no canto da janela a cada painel que termina. Sem som.")
            DuoToggle(isOn: $sound, title: "Som quando a equipe terminar",
                      detail: "Um som baixo \(Self.teamRule). Toca mesmo com o Duo na frente.")
            soundControls
            DuoToggle(isOn: $onlyInBackground, title: "Só tocar com o Duo em segundo plano",
                      detail: "Quando desligado, toca mesmo com o Duo na frente.")
                .padding(.leading, 36)
                .disabled(!sound)
                .opacity(sound ? 1 : 0.4)
            DuoToggle(isOn: $background, title: "Notificação do macOS quando a equipe terminar",
                      detail: "Com o Duo em segundo plano, uma notificação sem som \(Self.teamRule). Clicar nela volta para o painel.")
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 640, height: 520, alignment: .topLeading)
        .background(Theme.bg)
        .onChange(of: background) { _, on in if on { cockpit.notices.requestAuthorization() } }
    }
}

private struct AccountsSettings: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var cockpit: Cockpit
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.accounts) { account in
                        HStack {
                            Circle().fill(account.color).frame(width: 9, height: 9)
                            Text(account.name)
                        }
                        .tag(account.id)
                    }
                }
                HStack(spacing: 2) {
                    Button {
                        store.addAccount()
                        selection = store.accounts.last?.id
                    } label: { Text("+").frame(width: 12) }
                    .help("Adicionar conta")
                    Button {
                        if let id = selection { removeAccount(id) }
                    } label: { Text("−").frame(width: 12) }
                    .help("Remover conta")
                    .disabled(selection == nil || store.accounts.count <= 1)
                    Spacer()
                }
                .buttonStyle(.duo(.ghost, height: 22))
                .padding(6)
            }
            .frame(width: 180)

            Divider()

            if let id = selection, let account = store.account(id) {
                AccountEditor(account: account)
                    .id(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Selecione uma conta")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 640, height: 400)
        .onAppear { selection = selection ?? store.accounts.first?.id }
    }

    private func removeAccount(_ id: UUID) {
        guard let account = store.account(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Remover “\(account.name)”?"
        alert.informativeText = "Os painéis desta conta serão fechados. O login do Claude Code fica salvo em disco até você apagar a pasta da conta."
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        cockpit.discardAccount(id)
        store.remove(id)
        selection = store.accounts.first?.id
    }
}

private struct AccountEditor: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var cockpit: Cockpit
    @State var account: Account

    private var othersUsingDefault: Bool {
        store.accounts.contains { $0.id != account.id && $0.usesDefaultClaudeConfig }
    }

    var body: some View {
        Form {
            TextField("Nome", text: $account.name)

            ColorPicker("Cor", selection: Binding(
                get: { account.color },
                set: { account.colorHex = NSColor($0).hexString }
            ), supportsOpacity: false)

            Section("Claude Code") {
                Toggle("Usar o login padrão (~/.claude)", isOn: $account.usesDefaultClaudeConfig)
                if account.usesDefaultClaudeConfig && othersUsingDefault {
                    Label("Outra conta também usa ~/.claude — as duas teriam o mesmo login.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                LabeledContent("Configuração") {
                    HStack {
                        Text(account.effectiveConfigDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Mostrar") {
                            let dir = account.effectiveConfigDir
                            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                        .buttonStyle(.duo(.secondary, height: 22))
                    }
                }
                Text("Para entrar ou trocar de conta, rode /login num painel desta conta. Mudanças valem para novos painéis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("claude.ai") {
                Button("Sair do claude.ai nesta conta…") { logoutWeb() }
                    .buttonStyle(.duo(.secondary))
            }
        }
        .formStyle(.grouped)
        .onChange(of: account) { _, newValue in store.update(newValue) }
    }

    private func logoutWeb() {
        let alert = NSAlert()
        alert.messageText = "Sair do claude.ai em “\(account.name)”?"
        alert.informativeText = "Apaga cookies e dados do site só desta conta."
        alert.addButton(withTitle: "Sair")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let web = cockpit.web(for: account.id)
        Task { await web.clearData() }
    }
}

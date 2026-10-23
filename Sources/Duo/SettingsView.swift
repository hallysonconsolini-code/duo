import SwiftUI
import AppKit

struct SettingsView: View {
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

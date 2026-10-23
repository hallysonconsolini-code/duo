import SwiftUI
import AppKit

@main
struct DuoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var accounts: AccountStore
    @StateObject private var workspaces: WorkspaceStore
    @StateObject private var cockpit: Cockpit
    @StateObject private var updater: Updater
    @StateObject private var teams = TeamStore()

    init() {
        let accounts = AccountStore()
        let workspaces = WorkspaceStore()
        let cockpit = Cockpit(accounts: accounts, workspaces: workspaces)
        _accounts = StateObject(wrappedValue: accounts)
        _workspaces = StateObject(wrappedValue: workspaces)
        _cockpit = StateObject(wrappedValue: cockpit)
        let updater = Updater()
        updater.onWillRelaunch = {
            AppDelegate.skipQuitConfirmation = true
            workspaces.flushSave()
            cockpit.terminateAll()
        }
        _updater = StateObject(wrappedValue: updater)
        AppDelegate.cockpit = cockpit
        AppDelegate.updater = updater
    }

    var body: some Scene {
        Window("Duo", id: "main") {
            CockpitView()
                .environmentObject(accounts)
                .environmentObject(workspaces)
                .environmentObject(cockpit)
                .environmentObject(updater)
                .environmentObject(teams)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Procurar atualizações…") { updater.check(interactive: true) }
                    .disabled(updater.isBusy)
            }
            CommandGroup(replacing: .newItem) {
                Button("Novo painel") {
                    cockpit.addPane(kind: .claude, accountID: cockpit.focusedAccountID, askRole: true)
                }
                .keyboardShortcut("t", modifiers: .command)
                Button("Novo painel com outra conta") {
                    cockpit.addPane(kind: .claude, accountID: cockpit.otherAccountID, askRole: true)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Novo workspace…") { cockpit.openWorkspace() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Montar equipe neste workspace…") { cockpit.setUpTeamInSelectedWorkspace() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Fechar painel") { cockpit.closeFocusedPane() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandMenu("Painel") {
                Button(cockpit.zoomed ? "Sair do zoom" : "Zoom no painel") { cockpit.zoomed.toggle() }
                    .keyboardShortcut(.return, modifiers: .command)
                Divider()
                ForEach(1..<10) { n in
                    Button("Ir para painel \(n)") { cockpit.focusPane(number: n) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
                Divider()
                Button("Workspace anterior") { cockpit.cycleWorkspace(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Próximo workspace") { cockpit.cycleWorkspace(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
                .environmentObject(accounts)
                .environmentObject(cockpit)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var cockpit: Cockpit?
    @MainActor static var updater: Updater?
    @MainActor static var skipQuitConfirmation = false

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        InputSelection.install()
        Snapshot.scheduleIfRequested()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Self.updater?.check(interactive: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.cockpit?.workspaces.flushSave()
        guard !Self.skipQuitConfirmation, let cockpit = Self.cockpit, cockpit.anyRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Encerrar o Duo?"
        alert.informativeText = "Os Claude Code abertos serão encerrados. Os painéis reabrem e retomam as conversas na próxima vez."
        alert.addButton(withTitle: "Encerrar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        cockpit.terminateAll()
        return .terminateNow
    }
}

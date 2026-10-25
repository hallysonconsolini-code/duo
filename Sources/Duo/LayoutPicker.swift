import SwiftUI

/// Itens de layout do menu Painel e do menu de contexto da barra do painel: os modelos de
/// zonas (o atual marcado), equilibrar e remover zonas vazias.
struct LayoutMenuItems: View {
    @ObservedObject var cockpit: Cockpit
    @ObservedObject var workspaces: WorkspaceStore

    var body: some View {
        let current = workspaces.selected?.zoneLayout
        ForEach(cockpit.zoneTemplates) { template in
            Toggle(template.name, isOn: Binding(
                get: { current.map { template.layout.hasSameShape(as: $0) } ?? false },
                set: { _ in cockpit.applyTemplate(template) }
            ))
        }
        Divider()
        Button("Equilibrar zonas") { cockpit.balanceZones() }
        Button("Remover zonas vazias") { cockpit.removeEmptyZones() }
            .disabled(!(workspaces.selected.map(Self.hasEmptyZone) ?? false))
    }

    static func hasEmptyZone(_ ws: Workspace) -> Bool {
        ws.zoneLayout.zoneIDs.contains { z in !ws.panes.contains { $0.zone == z } }
    }
}

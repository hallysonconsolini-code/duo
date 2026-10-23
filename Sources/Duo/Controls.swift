import SwiftUI

// Controles próprios do Duo: fundo preto, fonte mono, linhas finas e vermelho de destaque.
// Substituem os Picker e botões no estilo padrão do macOS.

// MARK: Botões

/// Estilos de botão do Duo. Uso: `.buttonStyle(.duo(.primary))`.
struct DuoButtonStyle: ButtonStyle {
    enum Kind {
        /// Ação principal: vermelho preenchido.
        case primary
        /// Ação comum: contorno fino.
        case secondary
        /// Ação discreta: só texto, fundo no hover.
        case ghost
    }

    var kind: Kind = .secondary
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        DuoButtonBody(configuration: configuration, kind: kind, height: height)
    }
}

extension ButtonStyle where Self == DuoButtonStyle {
    static func duo(_ kind: DuoButtonStyle.Kind = .secondary, height: CGFloat = 26) -> DuoButtonStyle {
        DuoButtonStyle(kind: kind, height: height)
    }
}

private struct DuoButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DuoButtonStyle.Kind
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hover = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.mono(11, .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground(pressed))
            .padding(.horizontal, kind == .ghost ? 8 : 12)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 5).fill(fill(pressed)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }

    private func foreground(_ pressed: Bool) -> Color {
        guard isEnabled else { return kind == .primary ? Theme.text.opacity(0.35) : Theme.faint }
        switch kind {
        case .primary: return Theme.text
        case .secondary: return hover || pressed ? Theme.text : Theme.soft
        case .ghost: return hover || pressed ? Theme.text : Theme.dim
        }
    }

    private func fill(_ pressed: Bool) -> Color {
        switch kind {
        case .primary:
            guard isEnabled else { return Theme.accent.opacity(0.22) }
            return pressed ? Theme.accent.opacity(0.7) : (hover ? Theme.accent : Theme.accent.opacity(0.88))
        case .secondary:
            guard isEnabled else { return .clear }
            return pressed ? Theme.paneBorder : (hover ? Theme.bar : Theme.bar.opacity(0.6))
        case .ghost:
            guard isEnabled else { return .clear }
            return pressed ? Theme.paneBorder : (hover ? Theme.bar : .clear)
        }
    }

    private var border: Color {
        if isFocused && isEnabled { return Theme.accent.opacity(0.7) }
        switch kind {
        case .primary: return .clear
        case .secondary: return hover && isEnabled ? Theme.dim.opacity(0.6) : Theme.paneBorder
        case .ghost: return .clear
        }
    }
}

// MARK: Seletor de menu

/// Seletor de uma opção numa lista (ex.: conta). O controle fechado e a lista aberta
/// (num popover) são do Duo; Esc ou clicar fora fecha a lista.
struct DuoMenuPicker<Value: Hashable>: View {
    typealias Option = DuoMenuOption<Value>

    let options: [Option]
    @Binding var selection: Value
    var width: CGFloat = 120
    var placeholder = "—"

    @State private var open = false

    private var current: Option? { options.first { $0.value == selection } }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                if let color = current?.color {
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                Text(current?.label ?? placeholder)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("⌄").offset(y: -2).opacity(0.7)
            }
            .frame(width: width - 16)
        }
        .buttonStyle(MenuFieldStyle(open: open))
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        DuoMenuList(options: options, selection: selection, minWidth: max(width, 140)) { value in
            selection = value
            open = false
        }
    }
}

/// Uma opção de DuoMenuPicker / DuoMenuList.
struct DuoMenuOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var color: Color?
    /// Texto curto à direita, apagado (ex.: "2×1").
    var detail: String?
    var id: Value { value }
}

/// Lista de opções no visual do Duo, com a atual marcada. Feita para ir dentro de um popover.
struct DuoMenuList<Value: Hashable>: View {
    let options: [DuoMenuOption<Value>]
    let selection: Value
    var minWidth: CGFloat = 140
    let pick: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(options) { option in
                DuoMenuRow(option: option, active: option.value == selection) { pick(option.value) }
            }
        }
        .padding(4)
        .frame(minWidth: minWidth)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

/// Controle fechado do DuoMenuPicker: hover, foco e aberto acendem a borda.
private struct MenuFieldStyle: ButtonStyle {
    let open: Bool

    func makeBody(configuration: Configuration) -> some View {
        FieldBody(configuration: configuration, open: open)
    }

    private struct FieldBody: View {
        let configuration: ButtonStyleConfiguration
        let open: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var hover = false

        var body: some View {
            let lit = (hover || open || configuration.isPressed) && isEnabled
            configuration.label
                .font(Theme.mono(11))
                .foregroundStyle(isEnabled ? (lit ? Theme.text : Theme.soft) : Theme.faint)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(lit ? Theme.bar : Theme.bar.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(border(lit), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .onHover { hover = $0 }
        }

        private func border(_ lit: Bool) -> Color {
            if open || (isFocused && isEnabled) { return Theme.accent.opacity(0.7) }
            return lit ? Theme.dim.opacity(0.6) : Theme.paneBorder
        }
    }
}

private struct DuoMenuRow<Value: Hashable>: View {
    let option: DuoMenuOption<Value>
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(active ? "✓" : " ").font(Theme.mono(10, .bold)).foregroundStyle(Theme.accent).frame(width: 10)
                if let color = option.color {
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                Text(option.label)
                    .font(Theme.mono(11, active ? .bold : .regular))
                    .foregroundStyle(active || hover ? Theme.text : Theme.soft)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail = option.detail {
                    Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(hover ? Theme.accent.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Seletor segmentado

/// Poucas opções lado a lado (ex.: modelo, esforço), sem dropdown. A ativa fica na cor `tint`.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { value in
                Segment(text: label(value), active: value == selection, tint: tint) { selection = value }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bar.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.paneBorder, lineWidth: 1))
        .fixedSize()
    }

    private struct Segment: View {
        let text: String
        let active: Bool
        let tint: Color
        let action: () -> Void
        @State private var hover = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            Button(action: action) {
                Text(text)
                    .font(Theme.mono(10.5, active ? .bold : .regular))
                    .foregroundStyle(!isEnabled ? Theme.faint : active ? tint : (hover ? Theme.soft : Theme.dim))
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(active ? tint.opacity(0.14) : (hover ? Theme.paneBorder.opacity(0.6) : .clear)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(active ? tint.opacity(0.35) : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
        }
    }
}

// MARK: Contador

/// − n + compacto, com contorno (ex.: quantos de cada papel).
struct CountStepper: View {
    let value: Int
    var tint: Color = Theme.soft
    let help: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            GlyphButton(glyph: "−", help: "Remover \(help)", size: 11, action: decrement)
                .disabled(value == 0)
                .opacity(value == 0 ? 0.4 : 1)
            Text("\(value)")
                .font(Theme.mono(11, .bold))
                .foregroundStyle(value == 0 ? Theme.faint : tint)
                .frame(minWidth: 14)
            GlyphButton(glyph: "+", help: "Adicionar \(help)", size: 11, action: increment)
        }
        .padding(.horizontal, 2)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bar.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.paneBorder, lineWidth: 1))
    }
}

// MARK: Campo de texto

extension View {
    /// Campo de texto no visual do Duo. Usar com `.textFieldStyle(.plain)`.
    func duoField(width: CGFloat? = nil) -> some View {
        self
            .font(Theme.mono(11))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 8)
            .frame(width: width, height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bar))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.paneBorder, lineWidth: 1))
    }
}

// MARK: Título de seção

/// Título de seção legível: nome, uma linha de ajuda opcional e algo à direita (contagem, botão).
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.mono(12, .bold)).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: Interruptor

/// Liga/desliga no visual do Duo: título, explicação e um interruptor vermelho quando ligado.
struct DuoToggle: View {
    @Binding var isOn: Bool
    let title: String
    var detail: String?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Theme.accent.opacity(isEnabled ? 0.9 : 0.3) : Theme.bar)
                        .overlay(Capsule().strokeBorder(isOn ? .clear : (hover ? Theme.dim.opacity(0.6) : Theme.paneBorder), lineWidth: 1))
                    Circle()
                        .fill(isEnabled ? Theme.text : Theme.dim)
                        .padding(2)
                }
                .frame(width: 28, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.mono(11.5, .bold))
                        .foregroundStyle(isEnabled ? Theme.text : Theme.faint)
                    if let detail {
                        Text(detail)
                            .font(Theme.mono(10))
                            .foregroundStyle(isEnabled ? Theme.dim : Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

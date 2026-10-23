import SwiftUI
import AppKit

/// Paleta do cockpit: preto puro, linhas finas, vermelho como cor de destaque.
enum Theme {
    static let bg = Color.black
    static let nsBg = NSColor.black
    static let nsText = NSColor(hex: "#E2E8F0")

    static let paneBorder = Color(hex: "#1F2937")
    static let bar = Color(hex: "#101010")
    static let sep = Color(hex: "#111827")

    static let text = Color.white
    static let soft = Color(hex: "#B6B7C0")
    static let dim = Color(hex: "#6B7280")
    static let faint = Color(hex: "#4B5563")

    static let accent = Color(hex: "#EF4444")
    static let accentSoft = Color(hex: "#FECACA")
    static let green = Color(hex: "#34D399")
    static let yellow = Color(hex: "#FACC15")
    static let sky = Color(hex: "#38BDF8")

    static func mono(_ size: CGFloat = 11.5, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let trafficLightInset: CGFloat = 78

    static func color(for status: PaneStatus) -> Color {
        switch status {
        case .starting: faint
        case .idle: dim
        case .working: green
        case .attention: yellow
        case .exited: accent.opacity(0.7)
        }
    }
}

/// Rótulo de seção: caixa alta, pequeno, espaçado.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(9, .bold))
            .tracking(1.6)
            .foregroundStyle(Theme.faint)
    }
}

/// Etiqueta com fundo e borda na mesma cor, levemente transparentes.
struct Chip: View {
    let text: String
    let color: Color
    var bold = true
    var size: CGFloat = 10.5

    var body: some View {
        Text(text)
            .font(Theme.mono(size, bold ? .bold : .regular))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

/// Ponto de estado; pulsa enquanto o painel trabalha.
struct StatusDot: View {
    let status: PaneStatus
    var size: CGFloat = 6
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Theme.color(for: status))
            .frame(width: size, height: size)
            .opacity(status == .working && pulse ? 0.35 : 1)
            .animation(status == .working ? .easeInOut(duration: 0.7).repeatForever() : .default, value: pulse)
            .onAppear { pulse = true }
    }
}

/// Botão de texto/glifo discreto que acende no hover.
struct GlyphButton: View {
    let glyph: String
    let help: String
    var size: CGFloat = 12
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(glyph)
                .font(Theme.mono(size))
                .foregroundStyle(hover ? Theme.text : Theme.faint)
                .frame(minWidth: 18, minHeight: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Ajusta a NSWindow que hospeda a view: fundo preto, sem título, arrastável pelo fundo.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = Theme.nsBg
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

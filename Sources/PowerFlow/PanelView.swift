import AppKit
import PowerFlowCore
import SwiftUI

/// O painel que o item da barra abre.
struct PanelView: View {
    @ObservedObject var monitor: PowerMonitor
    @ObservedObject var navigation: PanelNavigation

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReduceMotion) private var forceReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        ZStack(alignment: .top) {
            PanelScreen(route: navigation.route, snapshot: monitor.snapshot, panel: monitor.panel,
                        samples: monitor.history.recent(seconds: 120),
                        open: { navigation.push($0, reduceMotion: reduceMotion) },
                        back: { navigation.pop(animated: true, reduceMotion: reduceMotion) })
                .id(navigation.route)
                .transition(navigation.transition(reduceMotion: reduceMotion))
        }
        .frame(width: PanelContent.width, alignment: .top)
        .clipped()
        .background {
            // Esc e ⌘[ voltam ao nível 1. No nível 1 não existem, e o Esc
            // fecha o painel, como em qualquer popover.
            if navigation.route != .main {
                Group {
                    Button("") { navigation.pop(animated: false, reduceMotion: reduceMotion) }
                        .keyboardShortcut(.cancelAction)
                    Button("") { navigation.pop(animated: false, reduceMotion: reduceMotion) }
                        .keyboardShortcut("[", modifiers: .command)
                }
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }
}

/// A vista de uma rota para um instantâneo. Não lê nada nem guarda estado,
/// por isso desenha-se igual ao vivo e no `--snapshot`.
struct PanelScreen: View {
    let route: PanelRoute
    let snapshot: PowerSnapshot
    let panel: PanelState
    let samples: [PowerHistory.Sample]
    let open: (PanelRoute) -> Void
    let back: () -> Void

    var body: some View {
        switch route {
        case .main:
            PanelContent(snapshot: snapshot, panel: panel, samples: samples, open: open)
        case .battery:
            BatteryDetailView(copy: BatteryCopy(snapshot: snapshot, panel: panel), back: back)
                .frame(width: PanelContent.width, alignment: .leading)
        case .apps:
            AppsView(total: PFFormat().watts(snapshot.systemTotal ?? 0), back: back)
                .frame(width: PanelContent.width, alignment: .leading)
        }
    }
}

/// O nível 1 do painel.
struct PanelContent: View {
    let snapshot: PowerSnapshot
    let panel: PanelState
    let samples: [PowerHistory.Sample]
    let open: (PanelRoute) -> Void

    static let width: CGFloat = 360

    var body: some View {
        let copy = PanelCopy(snapshot: snapshot, panel: panel)

        VStack(alignment: .leading, spacing: 0) {
            if panel.kind == .unavailable {
                UnavailableView(battery: snapshot.battery.isPresent
                                    ? BatteryCopy(snapshot: snapshot, panel: panel) : nil,
                                openBattery: { open(.battery) })
            } else {
                PanelHeader(copy: copy, origin: panel.origin)

                if panel.kind == .settling {
                    SettlingBar(remaining: snapshot.settleRemaining)
                        .padding(EdgeInsets(top: -4, leading: PFSpace.popoverMargin,
                                            bottom: PFSpace.m, trailing: PFSpace.popoverMargin))
                }

                if let banner = copy.banner {
                    PanelBanner(banner: banner)
                        .padding(EdgeInsets(top: 0, leading: PFSpace.popoverMargin,
                                            bottom: PFSpace.m, trailing: PFSpace.popoverMargin))
                }

                FlowDiagram(snapshot: snapshot, panel: panel, copy: copy,
                            openBattery: { open(.battery) })
                    .padding(EdgeInsets(top: PFSpace.xs, leading: PFSpace.popoverMargin,
                                        bottom: 14, trailing: PFSpace.popoverMargin))

                if !snapshot.breakdown.isEmpty {
                    separator
                    BreakdownView(slices: snapshot.breakdown, openApps: { open(.apps) })
                        .padding(EdgeInsets(top: PFSpace.m, leading: PFSpace.popoverMargin,
                                            bottom: 14, trailing: PFSpace.popoverMargin))
                }
                // O histórico ainda é o da v1; refaz-se na Fase 6.
                if samples.count > 2 {
                    separator
                    HistoryChart(samples: samples)
                        .padding(EdgeInsets(top: 10, leading: PFSpace.popoverMargin,
                                            bottom: PFSpace.m, trailing: PFSpace.popoverMargin))
                }
            }
        }
        .frame(width: Self.width, alignment: .leading)
    }

    private var separator: some View {
        Rectangle().fill(PFColor.sep).frame(height: 1)
    }
}

// MARK: - Cabeçalho

/// O número de destaque, de onde vem a energia e o que a bateria está a fazer.
private struct PanelHeader: View {
    let copy: PanelCopy
    let origin: PanelState.Origin

    /// Um ponto por fonte. A cor repete o que o texto ao lado já diz.
    private var dots: [FlowNodeKind] {
        switch origin {
        case .mains, .adapter:    return [.adapter]
        case .battery:            return [.battery]
        case .adapterAndBattery:  return [.adapter, .battery]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: PFSpace.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(copy.caption)
                        .pfType(.secondary)
                        .foregroundStyle(PFColor.fg2)

                    Text(copy.hero)
                        .pfType(.display)
                        .monospacedDigit()
                        .kerning(-0.28)
                        .foregroundStyle(copy.isDimmed ? PFColor.fg2 : PFColor.fg)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                PanelMenuButton()
            }

            // A terceira linha passa por baixo do botão e usa a largura toda:
            // com a coluna do protótipo, «valores estáveis dentro de 3 s» quebrava.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(dots, id: \.self) { node in
                        Circle().fill(node.color).frame(width: 8, height: 8)
                    }
                }
                .offset(y: -1)

                (Text(copy.origin).fontWeight(.semibold).foregroundColor(PFColor.fg)
                    + Text(copy.status.map { " · " + $0 } ?? "").foregroundColor(PFColor.fg2))
                    .pfType(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, PFSpace.xs)
            .accessibilityElement(children: .combine)
        }
        .accessibilityElement(children: .contain)
        .padding(EdgeInsets(top: 14, leading: PFSpace.popoverMargin, bottom: PFSpace.m,
                            trailing: PFSpace.m))
    }
}

// MARK: - Menu «…»

/// O botão «…» e o menu que ele abre.
struct PanelMenuButton: View {
    @StateObject private var menu = PanelMenu()
    @Environment(\.isStaticRender) private var isStaticRender

    var body: some View {
        Button { menu.show() } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PFColor.fg2)
        }
        .buttonStyle(PFIconButtonStyle(isOpen: menu.isOpen))
        // Numa imagem parada não há vistas do AppKit.
        .background { if !isStaticRender { MenuAnchor(menu: menu) } }
        .accessibilityLabel(L10n.string("more_vo"))
    }
}

/// Botão redondo de 28 pt, só com ícone: fundo `fill` com o ponteiro por cima,
/// premido ou com o menu aberto.
private struct PFIconButtonStyle: ButtonStyle {
    let isOpen: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background {
                Circle().fill(PFColor.fill)
                    .opacity(isHovering || isOpen || configuration.isPressed ? 1 : 0)
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { isHovering = $0 }
    }
}

/// O menu do painel. «Definições…» entra quando a janela existir (Fase 8).
@MainActor
private final class PanelMenu: NSObject, ObservableObject, NSMenuDelegate {
    @Published private(set) var isOpen = false
    weak var anchor: NSView?

    func show() {
        guard let anchor else { return }

        let menu = NSMenu()
        menu.delegate = self
        let about = menu.addItem(withTitle: L10n.string("m_about"),
                                 action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: L10n.string("m_quit"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp

        // Por baixo do botão, encostado à direita dele.
        let origin = NSPoint(x: anchor.bounds.maxX - menu.size.width, y: anchor.bounds.minY - 4)
        menu.popUp(positioning: nil, at: origin, in: anchor)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated { isOpen = true }
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated { isOpen = false }
    }
}

/// A vista do AppKit a que o menu se prende.
private struct MenuAnchor: NSViewRepresentable {
    let menu: PanelMenu

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        menu.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        menu.anchor = view
    }
}

// MARK: - Estabilização

/// A barra dos primeiros segundos, enquanto a média enche.
private struct SettlingBar: View {
    let remaining: Double

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReduceMotion) private var forceReduceMotion
    @Environment(\.isStaticRender) private var isStaticRender
    @State private var animated: CGFloat?

    /// Começa com um bocado visível, para se ler como barra e não como risco vazio.
    private var measured: CGFloat {
        let done = 1 - min(max(remaining / DualRateSmoother.settleDuration, 0), 1)
        return 0.08 + 0.92 * done
    }

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(PFColor.fill)
            Capsule().fill(PFColor.blue)
                .frame(width: proxy.size.width * (animated ?? measured))
        }
        .frame(height: 3)
        .accessibilityHidden(true)
        .onAppear {
            // Com Reduzir Movimento a barra não corre: avança a cada leitura.
            guard !systemReduceMotion, !forceReduceMotion, !isStaticRender, remaining > 0 else { return }
            animated = measured
            withAnimation(.linear(duration: remaining)) { animated = 1 }
        }
    }
}

// MARK: - Aviso

/// O aviso único do painel: porque não carrega, ou que a bateria está a ajudar.
private struct PanelBanner: View {
    let banner: PanelCopy.Banner

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: banner.isAttention ? "exclamationmark.circle.fill" : "info.circle.fill")
                .resizable()
                .foregroundStyle(banner.isAttention ? PFColor.amberInk : PFColor.fg2)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                if let title = banner.title {
                    Text(title).pfType(.title)
                }
                Text(banner.text).pfType(.secondary)
            }
            .foregroundStyle(PFColor.fg)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, PFSpace.m)
        .background {
            RoundedRectangle(cornerRadius: PFRadius.banner, style: .continuous)
                .fill(banner.isAttention ? PFColor.amberSoft : PFColor.fill)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sensores indisponíveis

/// A6: o SMC não deu as chaves de potência. A bateria vem do IORegistry e
/// continua a ler-se, por isso fica a linha que leva ao detalhe dela.
private struct UnavailableView: View {
    /// `nil` num Mac sem bateria.
    let battery: BatteryCopy?
    let openBattery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(PFColor.amberSoft)
                        .frame(width: 32, height: 32)
                        .overlay {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(PFColor.amberInk)
                        }
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    // O protótipo não tem o «…» aqui. Fica, porque até haver menu
                    // de clique direito é o único sítio de onde se sai da app.
                    PanelMenuButton()
                        .padding(.top, -6)
                        .padding(.trailing, -4)
                }

                Text(L10n.string("u_title"))
                    .font(PFFont.value)
                    .foregroundStyle(PFColor.fg)
                Text(L10n.string("u_body"))
                    .pfType(.body)
                    .foregroundStyle(PFColor.fg2)
                    .fixedSize(horizontal: false, vertical: true)

                // «Reportar no GitHub» aparece quando houver repositório (D3).
                Button(L10n.string("u_copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Diagnostics.report(), forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: PFSpace.xl, leading: PFSpace.popoverMargin,
                                bottom: PFSpace.l, trailing: PFSpace.popoverMargin))

            if let battery {
                Rectangle().fill(PFColor.sep).frame(height: 1)
                PanelNavRow(symbol: "battery.75", title: L10n.string("r_batt"),
                            summary: battery.rowSummary, action: openBattery)
                    .padding(EdgeInsets(top: PFSpace.xs, leading: PFSpace.s,
                                        bottom: PFSpace.s, trailing: PFSpace.s))
            }
        }
    }
}

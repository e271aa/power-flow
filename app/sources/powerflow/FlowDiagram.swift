import PowerFlowCore
import SwiftUI

/// Verdadeiro quando a interface é renderizada para uma imagem parada
/// (`--snapshot`). Aí não há camadas animadas, e as partículas desenham-se
/// congeladas para a imagem mostrar o mesmo que o ecrã.
private struct StaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

/// Liga Reduzir Movimento sem mexer na definição do sistema (`--reduce-motion`).
private struct ForceReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStaticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }

    var forceReduceMotion: Bool {
        get { self[ForceReduceMotionKey.self] }
        set { self[ForceReduceMotionKey.self] = newValue }
    }
}

extension FlowNodeKind {
    /// Traço e preenchimento. Nunca é texto.
    var color: Color {
        switch self {
        case .adapter: return PFColor.green
        case .system:  return PFColor.blue
        case .battery: return PFColor.amber
        }
    }

    var ink: Color {
        switch self {
        case .adapter: return PFColor.greenInk
        case .system:  return PFColor.blueInk
        case .battery: return PFColor.amberInk
        }
    }

    var soft: Color {
        switch self {
        case .adapter: return PFColor.greenSoft
        case .system:  return PFColor.blueSoft
        case .battery: return PFColor.amberSoft
        }
    }
}

/// Uma aresta com o caudal que a atravessa neste instante.
private struct FlowStream: Identifiable {
    let edge: FlowEdgeKind
    let curve: CubicCurve
    let flow: EdgeFlow

    var id: FlowEdgeKind { edge }

    var path: Path {
        var path = Path()
        path.move(to: curve.p0)
        path.addCurve(to: curve.p3, control1: curve.p1, control2: curve.p2)
        return path
    }

    /// De uma cor de nó para a outra, de porta a porta.
    var shading: GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [edge.from.color, edge.to.color]),
                        startPoint: curve.p0, endPoint: curve.p3)
    }

    /// As partículas levam as cores de tinta, como nas camadas ao vivo.
    var particleShading: GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [edge.from.ink, edge.to.ink]),
                        startPoint: curve.p0, endPoint: curve.p3)
    }
}

/// O diagrama de fluxo: os nós em cartão e a energia que passa entre eles.
///
/// O sentido lê-se parado: cada aresta com caudal tem um chevron fixo a meio
/// e a espessura do caudal. As partículas só acrescentam movimento.
struct FlowDiagram: View {
    let snapshot: PowerSnapshot
    let panel: PanelState
    let copy: PanelCopy
    /// O que o nó da bateria faz quando se clica. `nil`: é só um cartão.
    var openBattery: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forceReduceMotion) private var forceReduceMotion
    @Environment(\.isStaticRender) private var isStaticRender

    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        let streams = FlowLayout.edges(hasBattery: panel.showsBattery).map { edge in
            FlowStream(edge: edge, curve: FlowLayout.curve(edge),
                       flow: EdgeFlow(watts: snapshot.watts(on: edge),
                                      isSuppressed: panel.kind == .settling,
                                      isHeld: snapshot.heldEdges.contains(edge),
                                      reduceMotion: reduceMotion))
        }
        let looks = streams.map { EdgeLook(edge: $0.edge, flow: $0.flow) }

        ZStack(alignment: .topLeading) {
            // Ao vivo as arestas são camadas do Core Animation, que animam a
            // espessura e o acender sem a app desenhar fotogramas. Numa imagem
            // parada desenham-se aqui, com as partículas congeladas.
            if isStaticRender {
                Canvas { context, _ in
                    for stream in streams {
                        drawEdge(stream, in: &context)
                        drawFrozenParticles(stream, in: &context)
                    }
                }
                .accessibilityHidden(true)
            } else {
                FlowLayers(part: .edges, looks: looks, reduceMotion: reduceMotion)
                    .accessibilityHidden(true)
            }

            ForEach(Array(FlowLayout.nodes(hasBattery: panel.showsBattery).enumerated()), id: \.element) { index, node in
                let frame = FlowLayout.frame(of: node)
                card(for: node)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    // O VoiceOver lê os nós primeiro, pela ordem do handoff, e as arestas depois.
                    .accessibilitySortPriority(Double(10 - index))
            }

            // Os chevrons e as portas ficam por cima de tudo: as portas tapam
            // o sítio onde a aresta toca no nó.
            if isStaticRender {
                Canvas { context, _ in
                    for stream in streams {
                        if stream.flow.isActive { drawChevron(stream, in: &context) }
                        drawPorts(stream, in: &context)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            } else {
                FlowLayers(part: .marks, looks: looks, reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            ForEach(Array(streams.enumerated()), id: \.element.id) { index, stream in
                if let label = copy.voFlows[stream.edge] {
                    let middle = stream.curve.point(at: 0.5)
                    Color.clear
                        .frame(width: 24, height: 24)
                        .offset(x: middle.x - 12, y: middle.y - 12)
                        .accessibilityElement()
                        .accessibilityLabel(label)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilitySortPriority(Double(5 - index))
                }
            }
        }
        .frame(width: FlowLayout.width, height: FlowLayout.height(hasBattery: panel.showsBattery),
               alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.voDiagram)
    }

    // MARK: - Nós

    @ViewBuilder
    private func card(for node: FlowNodeKind) -> some View {
        switch node {
        case .adapter:
            NodeCard(node: node, symbol: "powerplug.fill", label: L10n.string("n_adapter"),
                     value: copy.adapter, isDimmed: copy.isDimmed,
                     isUnplugged: panel.origin == .battery)
                .accessibilityLabel(copy.voAdapter)
                .accessibilityAddTraits(.isStaticText)
        case .system:
            NodeCard(node: node, symbol: "cpu.fill", label: L10n.string("n_system"),
                     value: copy.system, isDimmed: copy.isDimmed, isUnplugged: false)
                .accessibilityLabel(copy.voSystem)
                .accessibilityAddTraits(.isStaticText)
        case .battery:
            let card = NodeCard(node: node, symbol: batterySymbol, label: copy.batteryLabel,
                                value: copy.battery, isDimmed: copy.isDimmed, isUnplugged: false,
                                showsDisclosure: openBattery != nil)
            if let openBattery {
                Button(action: openBattery) { card }
                    .buttonStyle(NodeButtonStyle())
                    .accessibilityLabel(copy.voBattery ?? "")
            } else {
                card.accessibilityLabel(copy.voBattery ?? "")
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private var batterySymbol: String {
        switch snapshot.battery.percentage {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }

    // MARK: - Desenho

    private func drawEdge(_ stream: FlowStream, in context: inout GraphicsContext) {
        guard stream.flow.isActive else {
            // Sem caudal fica o trilho, para a estrutura do diagrama se ler.
            context.stroke(stream.path, with: .color(PFColor.track),
                           style: StrokeStyle(lineWidth: EdgeFlow.trackWidth, lineCap: .round,
                                              dash: [3, 4]))
            return
        }

        var tube = context
        tube.opacity = 0.28
        tube.stroke(stream.path, with: stream.shading,
                    style: StrokeStyle(lineWidth: stream.flow.tubeWidth, lineCap: .butt))
        context.stroke(stream.path, with: stream.shading,
                       style: StrokeStyle(lineWidth: stream.flow.coreWidth, lineCap: .round))
    }

    /// As partículas num instante fixo: um ponto de 14 em 14 pt.
    private func drawFrozenParticles(_ stream: FlowStream, in context: inout GraphicsContext) {
        guard stream.flow.hasParticles else { return }
        context.stroke(stream.path, with: stream.particleShading,
                       style: StrokeStyle(lineWidth: stream.flow.particleDiameter, lineCap: .round,
                                          dash: [0, EdgeFlow.particleSpacing]))
    }

    private func drawChevron(_ stream: FlowStream, in context: inout GraphicsContext) {
        let chevron = FlowLayout.chevron(on: stream.curve, size: stream.flow.chevronSize)
        var path = Path()
        path.move(to: chevron.start)
        path.addLine(to: chevron.tip)
        path.addLine(to: chevron.end)

        // O halo separa o chevron do tubo que lhe passa por baixo.
        context.stroke(path, with: .color(PFColor.bg),
                       style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(stream.edge.from.ink),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }

    private func drawPorts(_ stream: FlowStream, in context: inout GraphicsContext) {
        let radius = FlowLayout.portRadius
        for (point, node) in [(stream.curve.p0, stream.edge.from), (stream.curve.p3, stream.edge.to)] {
            let port = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                              width: radius * 2, height: radius * 2))
            context.fill(port, with: .color(PFColor.bg))
            context.stroke(port, with: .color(stream.flow.isActive ? node.color : PFColor.track),
                           lineWidth: 1.6)
        }
    }
}

/// O cartão de um nó: mosaico com o símbolo, rótulo e valor.
private struct NodeCard: View {
    let node: FlowNodeKind
    let symbol: String
    let label: String
    let value: PanelCopy.NodeValue
    let isDimmed: Bool
    let isUnplugged: Bool
    /// O «›» de um nó que leva a outra vista.
    var showsDisclosure = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PFRadius.card, style: .continuous)

        HStack(spacing: PFSpace.s) {
            RoundedRectangle(cornerRadius: PFRadius.tile, style: .continuous)
                .fill(node.soft)
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(node.ink)
                }
                .opacity(isUnplugged ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 0) {
                // O rótulo quebra em vez de encolher: tem 11 pt, o mínimo. Duas
                // linhas e o valor ainda cabem nos 48 pt do cartão.
                Text(label)
                    .pfType(.minimum)
                    .foregroundStyle(PFColor.fg2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value.text)
                    .pfType(value.isWord ? .valueWord : .value)
                    .monospacedDigit()
                    .foregroundStyle(value.isWord || isDimmed ? PFColor.fg2 : PFColor.fg)
                    .animation(PFMotion.settleInk, value: isDimmed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDisclosure { PFDisclosure() }
        }
        .padding(.leading, 9)
        .padding(.trailing, showsDisclosure ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Desligado: o cartão e o símbolo esbatem-se e o contorno fica
        // tracejado, mas o texto não. A 60 % ficava a 2,3:1 no tema claro.
        .background {
            shape.fill(PFColor.node)
                .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                .opacity(isUnplugged ? 0.6 : 1)
        }
        .overlay {
            shape.strokeBorder(PFColor.nodeBorder,
                               style: StrokeStyle(lineWidth: 1, dash: isUnplugged ? [3, 3] : []))
                .opacity(isUnplugged ? 0.6 : 1)
        }
        .accessibilityElement(children: .ignore)
    }
}

/// O nó que é botão: com o ponteiro por cima leva um anel de 3 pt.
private struct NodeButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let ring = RoundedRectangle(cornerRadius: PFRadius.card + 3, style: .continuous)
        configuration.label
            .background {
                ring.fill(PFColor.fill)
                    .padding(-3)
                    .opacity(isHovering || configuration.isPressed ? 1 : 0)
            }
            // O anel de foco segue esta forma: com um retângulo saía de cantos retos.
            .contentShape(RoundedRectangle(cornerRadius: PFRadius.card, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { isHovering = $0 }
    }
}

import PowerFlowCore
import SwiftUI

/// Verdadeiro quando a interface é renderizada para uma imagem parada
/// (`--snapshot`). Aí não há camadas animadas, e as partículas desenham-se
/// congeladas para a imagem mostrar o mesmo que o ecrã.
private struct StaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isStaticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }
}

/// O diagrama de fluxo: três nós e as correntes de energia entre eles.
struct FlowDiagram: View {
    let snapshot: PowerSnapshot
    let panel: PanelState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isStaticRender) private var isStaticRender

    /// Altura do diagrama completo. A geometria calcula-se sempre para ela.
    private static let height: CGFloat = 235
    /// Sem bateria fica só a fila de cima, com os nós onde sempre estiveram.
    private static let heightWithoutBattery: CGFloat = 116

    var body: some View {
        GeometryReader { proxy in
            let geometry = FlowGeometry(size: CGSize(width: proxy.size.width,
                                                     height: Self.height))
            let streams = streams(in: geometry)

            ZStack {
                // Os trilhos só mudam quando chega uma leitura, por isso
                // desenham-se uma vez por leitura e não por fotograma.
                Canvas { context, _ in
                    for stream in streams {
                        drawTrack(stream, in: &context)
                        if isStaticRender { drawFrozenParticles(stream, in: &context) }
                    }
                }
                if !isStaticRender {
                    ParticleLayer(streams: streams)
                }
                nodes(in: geometry)
            }
        }
        .frame(height: panel.showsBattery ? Self.height : Self.heightWithoutBattery)
    }

    // MARK: - Correntes

    private func streams(in geometry: FlowGeometry) -> [FlowStream] {
        var flows: [(FlowNode, FlowNode, Double)] = [
            (.adapter, .system, snapshot.adapterToSystem),
        ]
        if panel.showsBattery {
            flows.append((.adapter, .battery, snapshot.adapterToBattery))
            flows.append((.battery, .system, snapshot.batteryToSystem))
        }
        return flows.map { from, to, watts in
            FlowStream(edge: geometry.edge(from: from, to: to),
                       flow: EdgeFlow(watts: watts, reduceMotion: reduceMotion))
        }
    }

    // MARK: - Desenho

    private func drawTrack(_ stream: FlowStream, in context: inout GraphicsContext) {
        // Trilho: sempre visível, para a estrutura do diagrama se ler
        // mesmo quando não passa energia por ali.
        context.stroke(
            stream.edge.path,
            with: .color(stream.tint.opacity(stream.flow.isActive ? 0.22 : 0.10)),
            style: StrokeStyle(lineWidth: stream.flow.lineWidth, lineCap: .round)
        )
    }

    /// As partículas num instante fixo, repartidas pelo caminho.
    private func drawFrozenParticles(_ stream: FlowStream, in context: inout GraphicsContext) {
        let count = stream.flow.particleCount
        let radius = CGFloat(stream.flow.particleRadius)

        for index in 0..<count {
            let t = Double(index) / Double(count)
            let point = stream.edge.point(at: CGFloat(t))
            let opacity = min(1, max(0, min(t, 1 - t) / 0.12))

            let rect = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(stream.tint.opacity(0.95 * opacity)))
        }
    }

    // MARK: - Nós

    @ViewBuilder
    private func nodes(in geometry: FlowGeometry) -> some View {
        let visible: [FlowNode] = panel.showsBattery
            ? [.adapter, .battery, .system] : [.adapter, .system]
        ForEach(visible, id: \.self) { node in
            NodeBadge(node: node,
                      radius: geometry.nodeRadius,
                      watts: watts(for: node),
                      caption: caption(for: node),
                      isDimmed: isDimmed(node))
                .position(geometry.center(of: node))
        }
    }

    private func watts(for node: FlowNode) -> Double {
        switch node {
        // O que sai do nó, não a leitura em bruto: assim o número do
        // adaptador é sempre a soma das setas que dele partem, e o diagrama
        // não mostra energia a desaparecer pelo caminho.
        case .adapter: return snapshot.adapterToSystem + snapshot.adapterToBattery
        case .battery: return snapshot.adapterToBattery + snapshot.batteryToSystem
        case .system:  return snapshot.systemTotal ?? 0
        }
    }

    private func caption(for node: FlowNode) -> String? {
        switch node {
        case .adapter:
            // A potência máxima do adaptador já aparece no rodapé; repeti-la
            // aqui punha texto por cima da aresta que desce para a bateria.
            return panel.origin == .battery ? "desligado" : nil
        case .battery:
            switch panel.batteryActivity {
            case .charging:  return "a carregar"
            case .supplying: return "a descarregar"
            case .idle:      return "\(snapshot.battery.percentage) %"
            }
        case .system:
            return nil
        }
    }

    private func isDimmed(_ node: FlowNode) -> Bool {
        node == .adapter && panel.origin == .battery
    }
}

/// O círculo de um nó, com símbolo, potência e legenda.
///
/// A potência vai dentro do círculo de propósito: com ela por baixo, as
/// três linhas de texto cresciam para cima das arestas e o diagrama ficava
/// ilegível nas larguras de uma janela de barra de menus.
private struct NodeBadge: View {
    let node: FlowNode
    let radius: CGFloat
    let watts: Double
    let caption: String?
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(node.tint.opacity(isDimmed ? 0.06 : 0.15))
                Circle()
                    .strokeBorder(node.tint.opacity(isDimmed ? 0.25 : 0.55), lineWidth: 1.5)

                VStack(spacing: 1) {
                    Image(systemName: node.symbol)
                        .font(.system(size: radius * 0.42, weight: .medium))
                        .foregroundStyle(node.tint.opacity(isDimmed ? 0.4 : 0.95))
                    Text(isDimmed ? "—" : String(format: "%.1f", watts))
                        .font(.system(size: radius * 0.44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isDimmed ? .secondary : .primary)
                    Text("W")
                        .font(.system(size: radius * 0.26, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(isDimmed ? 0 : 1)
                }
            }
            .frame(width: radius * 2, height: radius * 2)

            Text(node.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: radius * 2.7)
    }
}

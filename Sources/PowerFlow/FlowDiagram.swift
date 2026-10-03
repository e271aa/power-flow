import PowerFlowCore
import SwiftUI

/// O diagrama de fluxo: três nós e as correntes de energia entre eles.
struct FlowDiagram: View {
    let snapshot: PowerSnapshot

    var body: some View {
        GeometryReader { proxy in
            let geometry = FlowGeometry(size: proxy.size)

            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { context, _ in
                        let phase = timeline.date.timeIntervalSinceReferenceDate
                        for stream in streams(in: geometry) {
                            draw(stream, in: &context, phase: phase)
                        }
                    }
                }
                nodes(in: geometry)
            }
        }
    }

    // MARK: - Correntes

    /// Uma aresta com o caudal que a atravessa neste instante.
    private struct Stream {
        let edge: FlowEdge
        let watts: Double
        var tint: Color { edge.from.tint }
    }

    private func streams(in geometry: FlowGeometry) -> [Stream] {
        [
            Stream(edge: geometry.edge(from: .adapter, to: .system),
                   watts: snapshot.adapterToSystem),
            Stream(edge: geometry.edge(from: .adapter, to: .battery),
                   watts: snapshot.adapterToBattery),
            Stream(edge: geometry.edge(from: .battery, to: .system),
                   watts: snapshot.batteryToSystem),
        ]
    }

    // MARK: - Desenho

    /// Abaixo deste caudal a aresta desenha-se apagada e sem partículas.
    private static let idleThreshold: Double = 0.15

    private func draw(_ stream: Stream, in context: inout GraphicsContext, phase: TimeInterval) {
        let isActive = stream.watts > Self.idleThreshold

        // Trilho: sempre visível, para a estrutura do diagrama se ler
        // mesmo quando não passa energia por ali.
        context.stroke(
            stream.edge.path,
            with: .color(stream.tint.opacity(isActive ? 0.22 : 0.10)),
            style: StrokeStyle(lineWidth: isActive ? lineWidth(for: stream.watts) : 2,
                               lineCap: .round)
        )

        guard isActive else { return }

        let count = particleCount(for: stream.watts)
        let speed = particleSpeed(for: stream.watts)
        let offset = phase * speed
        let radius = particleRadius(for: stream.watts)

        for index in 0..<count {
            let t = (offset + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
            let point = stream.edge.point(at: CGFloat(t))

            // Desvanece nos extremos para as partículas nascerem e morrerem
            // suavemente em vez de piscarem ao chegar ao nó.
            let fade = min(t, 1 - t) / 0.12
            let opacity = min(1, max(0, fade))

            let rect = CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect),
                         with: .color(stream.tint.opacity(0.95 * opacity)))
        }
    }

    /// Espessura, número, velocidade e tamanho crescem com o caudal, mas em
    /// raiz quadrada: entre 1 W e 60 W a diferença linear seria tão grande
    /// que os caudais pequenos ficariam invisíveis.
    private func scaled(_ watts: Double) -> Double {
        min(sqrt(max(watts, 0)) / sqrt(60), 1)
    }

    private func lineWidth(for watts: Double) -> CGFloat {
        2 + CGFloat(scaled(watts)) * 4
    }

    private func particleCount(for watts: Double) -> Int {
        3 + Int(scaled(watts) * 9)
    }

    private func particleSpeed(for watts: Double) -> Double {
        0.10 + scaled(watts) * 0.45
    }

    private func particleRadius(for watts: Double) -> CGFloat {
        1.8 + CGFloat(scaled(watts)) * 2.2
    }

    // MARK: - Nós

    @ViewBuilder
    private func nodes(in geometry: FlowGeometry) -> some View {
        ForEach([FlowNode.adapter, .battery, .system], id: \.self) { node in
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
            return snapshot.source == .adapter ? nil : "desligado"
        case .battery:
            if snapshot.adapterToBattery > FlowDiagram.idleThreshold { return "a carregar" }
            if snapshot.batteryToSystem > FlowDiagram.idleThreshold { return "a descarregar" }
            return "\(snapshot.battery.percentage) %"
        case .system:
            return nil
        }
    }

    private func isDimmed(_ node: FlowNode) -> Bool {
        node == .adapter && snapshot.source == .battery
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
        .animation(.easeOut(duration: 0.45), value: watts)
    }
}

import AppKit
import PowerFlowCore
import SwiftUI

/// Uma aresta com o caudal que a atravessa neste instante.
struct FlowStream {
    let edge: FlowEdge
    let flow: EdgeFlow
    var tint: Color { edge.from.tint }
}

/// As partículas das arestas, animadas pelo Core Animation.
///
/// Cada partícula é uma camada com uma animação que se repete, entregue ao
/// servidor de renderização. A app não desenha fotogramas: só mexe nas
/// camadas quando chega uma leitura nova. Com `TimelineView` + `Canvas` era
/// a app a redesenhar tudo a cada fotograma, e isso custava 13 % de CPU a
/// 30 fps e 20 % sem limite.
struct ParticleLayer: NSViewRepresentable {
    let streams: [FlowStream]

    func makeNSView(context: Context) -> ParticleHostView {
        ParticleHostView()
    }

    func updateNSView(_ view: ParticleHostView, context: Context) {
        view.streams = streams
    }
}

final class ParticleHostView: NSView {
    var streams: [FlowStream] = [] {
        didSet { sync() }
    }

    /// As partículas de uma aresta. A camada de fora leva a velocidade; as
    /// de dentro percorrem o caminho numa unidade de tempo dela.
    private struct Group {
        let container: CALayer
        let shape: Shape
    }

    /// O que obriga a refazer as camadas de uma aresta. A velocidade e o
    /// tamanho não entram: mudam a cada leitura e ajustam-se no sítio.
    private struct Shape: Equatable {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        let count: Int
        let height: CGFloat
    }

    private struct Key: Hashable {
        let from: FlowNode
        let to: FlowNode
    }

    private var groups: [Key: Group] = [:]

    /// Pontos com que se aproxima a curva. Com 24 troços, o desvio à Bézier
    /// fica muito abaixo de um ponto de ecrã.
    private static let pathSegments = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é usado")
    }

    /// As partículas são decoração: os cliques passam para o que está por baixo.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// O Core Animation deita fora as animações de uma camada que sai da
    /// janela, por isso refazem-se quando a vista entra numa.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeAllGroups()
        sync()
    }

    override func layout() {
        super.layout()
        sync()
    }

    /// As camadas das partículas, para a verificação do painel.
    var particleLayers: [CALayer] {
        groups.values.flatMap { $0.container.sublayers ?? [] }
    }

    private func removeAllGroups() {
        groups.values.forEach { $0.container.removeFromSuperlayer() }
        groups.removeAll()
    }

    private func sync() {
        guard let root = layer, window != nil else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let parentNow = root.convertTime(CACurrentMediaTime(), from: nil)
        var live = Set<Key>()

        for stream in streams where stream.flow.particleCount > 0 {
            let key = Key(from: stream.edge.from, to: stream.edge.to)
            let shape = Shape(start: stream.edge.start, control: stream.edge.control,
                              end: stream.edge.end, count: stream.flow.particleCount,
                              height: bounds.height)
            live.insert(key)

            let container: CALayer
            if let group = groups[key], group.shape == shape {
                container = group.container
            } else {
                // Refaz a aresta, mas continua do ponto do percurso em que
                // a anterior ia, para as partículas não voltarem ao início.
                let previous = groups[key]?.container
                let elapsed = previous?.convertTime(parentNow, from: root) ?? 0
                previous?.removeFromSuperlayer()

                container = CALayer()
                container.frame = bounds
                container.timeOffset = elapsed
                container.beginTime = parentNow
                container.speed = Float(stream.flow.particleSpeed)
                root.addSublayer(container)
                addParticles(to: container, for: stream, shape: shape)
                groups[key] = Group(container: container, shape: shape)
            }

            setSpeed(Float(stream.flow.particleSpeed), of: container, in: root, at: parentNow)
            let radius = CGFloat(stream.flow.particleRadius)
            for dot in container.sublayers ?? [] {
                dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
                dot.cornerRadius = radius
            }
        }

        for (key, group) in groups where !live.contains(key) {
            group.container.removeFromSuperlayer()
            groups[key] = nil
        }
    }

    /// Muda a velocidade sem as partículas saltarem: fixa o ponto do
    /// percurso em que estão agora e conta a nova velocidade a partir daí.
    private func setSpeed(_ speed: Float, of container: CALayer,
                          in root: CALayer, at parentNow: CFTimeInterval) {
        guard container.speed != speed else { return }
        let elapsed = container.convertTime(parentNow, from: root)
        container.timeOffset = elapsed
        container.beginTime = parentNow
        container.speed = speed
    }

    private func addParticles(to container: CALayer, for stream: FlowStream, shape: Shape) {
        // O SwiftUI conta o y de cima para baixo; uma camada do AppKit, de
        // baixo para cima. A conversão faz-se aqui, ponto a ponto.
        let points: [CGPoint] = (0...Self.pathSegments).map { step in
            let point = stream.edge.point(at: CGFloat(step) / CGFloat(Self.pathSegments))
            return CGPoint(x: point.x, y: shape.height - point.y)
        }
        let color = NSColor(stream.tint).withAlphaComponent(0.95).cgColor
        let now = container.convertTime(CACurrentMediaTime(), from: nil)

        for index in 0..<shape.count {
            let phase = Double(index) / Double(shape.count)

            let dot = CALayer()
            dot.backgroundColor = color
            dot.position = points[Int(phase * Double(Self.pathSegments))]

            // A posição segue o parâmetro da curva, como no desenho antigo,
            // e não o comprimento do arco.
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = points.map { NSValue(point: $0) }
            move.calculationMode = .linear

            // Desvanece nos extremos para as partículas nascerem e morrerem
            // suavemente em vez de piscarem ao chegar ao nó.
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.12, 0.88, 1]

            let loop = CAAnimationGroup()
            loop.animations = [move, fade]
            loop.duration = 1
            loop.repeatCount = .infinity
            // Começou «no passado», para as partículas ficarem repartidas
            // pelo caminho em vez de saírem todas do mesmo ponto.
            loop.beginTime = now - phase
            loop.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30,
                                                            preferred: 30)
            dot.add(loop, forKey: "flow")
            container.addSublayer(dot)
        }
    }
}

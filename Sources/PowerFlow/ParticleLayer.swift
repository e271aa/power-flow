import AppKit
import PowerFlowCore
import SwiftUI

/// As partículas de uma aresta: que caminho, com que tamanho e a que velocidade.
struct ParticleStream: Equatable {
    let edge: FlowEdgeKind
    let diameter: Double
    /// Pontos por segundo.
    let speed: Double
}

/// As partículas das arestas, animadas pelo Core Animation.
///
/// Cada aresta é um gradiente, nas cores de tinta, recortado por um traço de pontos (traço de
/// comprimento zero com pontas redondas, de 14 em 14 pt). O que anima é a fase
/// do tracejado, entregue ao servidor de renderização. A app não desenha
/// fotogramas: só mexe nas camadas quando chega uma leitura nova. Com
/// `TimelineView` + `Canvas` era a app a redesenhar tudo a cada fotograma, e
/// isso custava 13 % de CPU a 30 fps e 20 % sem limite.
struct ParticleLayer: NSViewRepresentable {
    let streams: [ParticleStream]

    func makeNSView(context: Context) -> ParticleHostView {
        ParticleHostView()
    }

    func updateNSView(_ view: ParticleHostView, context: Context) {
        view.streams = streams
    }
}

final class ParticleHostView: NSView {
    var streams: [ParticleStream] = [] {
        didSet { if streams != oldValue { sync() } }
    }

    private struct Group {
        let gradient: CAGradientLayer
        let dots: CAShapeLayer
        var speed: Double
    }

    private var groups: [FlowEdgeKind: Group] = [:]
    private var builtSize: CGSize = .zero

    private static let phaseKey = "lineDashPhase"
    private static let spacing = EdgeFlow.particleSpacing

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
        if bounds.size != builtSize { removeAllGroups() }
        sync()
    }

    /// As cores das camadas não seguem a aparência sozinhas.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        removeAllGroups()
        sync()
    }

    /// A fase do tracejado de cada aresta neste instante, lida da camada que
    /// o Core Animation está a apresentar. Serve a verificação do painel.
    var particlePhases: [CGFloat] {
        groups.values.compactMap { $0.dots.presentation()?.lineDashPhase }
    }

    private func removeAllGroups() {
        groups.values.forEach { $0.gradient.removeFromSuperlayer() }
        groups.removeAll()
    }

    private func sync() {
        guard let root = layer, window != nil, bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        builtSize = bounds.size
        var live = Set<FlowEdgeKind>()

        for stream in streams {
            live.insert(stream.edge)
            var group = groups[stream.edge] ?? makeGroup(for: stream.edge, in: root)
            group.dots.lineWidth = stream.diameter

            // Uma leitura nova mexe na velocidade por pouco. Só se troca a
            // animação quando a diferença se vê, e continua de onde ia.
            if group.dots.animation(forKey: Self.phaseKey) == nil
                || abs(group.speed - stream.speed) > 1 {
                let phase = group.dots.presentation()?.lineDashPhase ?? 0
                let move = CABasicAnimation(keyPath: Self.phaseKey)
                move.fromValue = phase
                move.toValue = phase - Self.spacing
                move.duration = Self.spacing / stream.speed
                move.repeatCount = .infinity
                move.timingFunction = CAMediaTimingFunction(name: .linear)
                move.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30,
                                                                preferred: 30)
                group.dots.add(move, forKey: Self.phaseKey)
                group.speed = stream.speed
            }
            groups[stream.edge] = group
        }

        for (edge, group) in groups where !live.contains(edge) {
            group.gradient.removeFromSuperlayer()
            groups[edge] = nil
        }
    }

    private func makeGroup(for edge: FlowEdgeKind, in root: CALayer) -> Group {
        let curve = FlowLayout.curve(edge)
        let height = bounds.height

        // O SwiftUI conta o y de cima para baixo; uma camada do AppKit, de
        // baixo para cima. A conversão faz-se aqui, ponto a ponto.
        func flipped(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: height - point.y) }
        func unit(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x / bounds.width, y: 1 - point.y / height)
        }

        let path = CGMutablePath()
        path.move(to: flipped(curve.p0))
        path.addCurve(to: flipped(curve.p3), control1: flipped(curve.p1), control2: flipped(curve.p2))

        let dots = CAShapeLayer()
        dots.frame = bounds
        dots.path = path
        dots.fillColor = nil
        dots.strokeColor = NSColor.black.cgColor
        dots.lineCap = .round
        dots.lineDashPattern = [0, NSNumber(value: Self.spacing)]

        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.startPoint = unit(curve.p0)
        gradient.endPoint = unit(curve.p3)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            gradient.colors = [NSColor(edge.from.ink).cgColor, NSColor(edge.to.ink).cgColor]
        }
        gradient.mask = dots
        root.addSublayer(gradient)

        return Group(gradient: gradient, dots: dots, speed: 0)
    }
}

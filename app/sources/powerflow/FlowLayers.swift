import AppKit
import PowerFlowCore
import SwiftUI

/// O que as camadas de uma aresta mostram numa leitura.
struct EdgeLook: Equatable {
    let edge: FlowEdgeKind
    var isActive: Bool
    let tubeWidth: Double
    let coreWidth: Double
    let chevronSize: Double
    var hasParticles: Bool
    let particleDiameter: Double
    /// Pontos por segundo.
    let particleSpeed: Double

    /// A mesma aresta, apagada, com a espessura que tinha.
    init(previous: EdgeLook, isActive: Bool) {
        self = previous
        self.isActive = isActive
        hasParticles = false
    }

    init(edge: FlowEdgeKind, flow: EdgeFlow) {
        self.edge = edge
        isActive = flow.isActive
        tubeWidth = flow.tubeWidth
        coreWidth = flow.coreWidth
        chevronSize = flow.chevronSize
        hasParticles = flow.hasParticles
        particleDiameter = flow.particleDiameter
        particleSpeed = flow.particleSpeed
    }
}

/// As arestas do diagrama em camadas do Core Animation.
///
/// Duas vistas: `.edges` fica por baixo dos nós (trilho, tubo, núcleo e
/// partículas) e `.marks` por cima (chevron e portas, que tapam o sítio onde a
/// aresta toca no nó). A app não desenha fotogramas: a cada leitura muda
/// umas propriedades e o servidor de renderização anima-as. Com o `Canvas`
/// redesenhado pela app, animar a espessura a cada leitura era o custo de
/// 13 % de CPU da Fase 0.
///
/// Movimento (handoff): a espessura muda em 0,45 s easeOut; uma aresta acende
/// em 0,25 s easeOut, com o chevron de 0,6 para 1, e apaga-se da mesma
/// maneira (a espera de 1 s é do modelo, `EdgeHold`). Com Reduzir Movimento a
/// espessura muda de uma vez e acender ou apagar é um fade de 0,15 s.
struct FlowLayers: NSViewRepresentable {
    enum Part { case edges, marks }

    let part: Part
    let looks: [EdgeLook]
    let reduceMotion: Bool

    func makeNSView(context: Context) -> FlowLayerHost {
        FlowLayerHost(part: part)
    }

    func updateNSView(_ view: FlowLayerHost, context: Context) {
        view.reduceMotion = reduceMotion
        view.looks = looks
    }
}

final class FlowLayerHost: NSView {
    let part: FlowLayers.Part
    var reduceMotion = false
    var looks: [EdgeLook] = [] {
        didSet { if looks != oldValue { sync(animated: true) } }
    }

    /// As camadas de uma aresta. Só se usam as da parte desta vista.
    private final class Group {
        let root = CALayer()
        // .edges
        let track = CAShapeLayer()
        let lit = CALayer()
        let tube = CAGradientLayer()
        let tubeMask = CAShapeLayer()
        let core = CAGradientLayer()
        let coreMask = CAShapeLayer()
        let particles = CAGradientLayer()
        let dots = CAShapeLayer()
        var speed: Double = 0
        // .marks
        let chevron = CALayer()
        let halo = CAShapeLayer()
        let ink = CAShapeLayer()
        var ports: [(layer: CAShapeLayer, node: FlowNodeKind)] = []

        var look: EdgeLook?
    }

    private var groups: [FlowEdgeKind: Group] = [:]
    private var builtSize: CGSize = .zero

    private static let phaseKey = "lineDashPhase"
    private static let spacing = EdgeFlow.particleSpacing
    /// Uma diferença de espessura menor do que isto não se vê: muda sem animar.
    private static let visibleChange = 0.25
    private static let chevronBox: CGFloat = 40

    init(part: FlowLayers.Part) {
        self.part = part
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é usado")
    }

    /// São decoração: os cliques passam para o que está por baixo.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// O Core Animation deita fora as animações de uma camada que sai da
    /// janela, por isso refazem-se quando a vista entra numa.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuild()
    }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { rebuild() }
    }

    /// As cores das camadas não seguem a aparência sozinhas.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    private func rebuild() {
        groups.values.forEach { $0.root.removeFromSuperlayer() }
        groups.removeAll()
        sync(animated: false)
    }

    // MARK: - Leituras para a verificação e para a sonda

    /// A fase do tracejado de cada aresta com partículas neste instante.
    var particlePhases: [CGFloat] {
        groups.values.filter { $0.dots.animation(forKey: Self.phaseKey) != nil }
            .compactMap { $0.dots.presentation()?.lineDashPhase }
    }

    /// O que está a ser apresentado em cada aresta: opacidade da parte acesa,
    /// espessura do tubo (ou escala do chevron) e fase das partículas.
    var presented: [FlowEdgeKind: [Double]] {
        groups.mapValues { group in
            switch part {
            case .edges:
                let lit = group.lit.presentation() ?? group.lit
                let mask = group.tubeMask.presentation() ?? group.tubeMask
                let dots = group.dots.presentation() ?? group.dots
                return [Double(lit.opacity), Double(mask.lineWidth), Double(dots.lineDashPhase)]
            case .marks:
                let chevron = group.chevron.presentation() ?? group.chevron
                return [Double(chevron.opacity), Double(chevron.transform.m11)]
            }
        }
    }

    // MARK: - Camadas

    private func sync(animated: Bool) {
        guard let root = layer, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        builtSize = bounds.size

        var live = Set<FlowEdgeKind>()
        for (index, look) in looks.enumerated() {
            live.insert(look.edge)
            if let group = groups[look.edge] {
                update(group, to: look, animated: animated)
            } else {
                let group = makeGroup(for: look.edge, order: index, in: root)
                groups[look.edge] = group
                update(group, to: look, animated: false)
            }
        }
        for (edge, group) in groups where !live.contains(edge) {
            group.root.removeFromSuperlayer()
            groups[edge] = nil
        }
    }

    private func update(_ group: Group, to look: EdgeLook, animated: Bool) {
        let previous = group.look
        group.look = look
        let switching = previous.map { $0.isActive != look.isActive } ?? false

        // 1. Acender ou apagar.
        CATransaction.begin()
        if !animated || !switching {
            CATransaction.setDisableActions(true)
        } else {
            CATransaction.setAnimationDuration(reduceMotion ? 0.15 : 0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }
        if animated, switching, !look.isActive {
            // As partículas continuam enquanto a aresta se apaga e saem no fim:
            // uma animação numa camada invisível ainda obriga a compor fotogramas.
            CATransaction.setCompletionBlock { [weak self, weak group] in
                guard let self, let group, group.look?.isActive == false else { return }
                self.stopParticles(group)
            }
        }
        switch part {
        case .edges:
            group.track.opacity = look.isActive ? 0 : 1
            group.lit.opacity = look.isActive ? 1 : 0
        case .marks:
            group.chevron.opacity = look.isActive ? 1 : 0
            for port in group.ports {
                port.layer.strokeColor = resolved(look.isActive ? port.node.color : PFColor.track)
            }
        }
        CATransaction.commit()

        if part == .marks {
            // Com Reduzir Movimento o chevron não cresce: só aparece.
            CATransaction.begin()
            if !animated || !switching || reduceMotion {
                CATransaction.setDisableActions(true)
            } else {
                CATransaction.setAnimationDuration(0.25)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            }
            let small = !look.isActive && !reduceMotion
            group.chevron.transform = small ? CATransform3DMakeScale(0.6, 0.6, 1) : CATransform3DIdentity
            CATransaction.commit()
        }

        // 2. A espessura. Só anima numa aresta que já estava acesa e continua.
        // Uma aresta que se apaga desvanece com a espessura que tinha.
        if animated, !look.isActive, previous != nil {
            group.look = EdgeLook(previous: previous!, isActive: false)
        } else {
            setWidths(group, from: previous, to: look, animated: animated, switching: switching)
        }

        // 3. As partículas.
        if part == .edges {
            if look.hasParticles {
                startParticles(group, speed: look.particleSpeed)
            } else if look.isActive || !animated {
                stopParticles(group)
            }
        }
    }

    private func setWidths(_ group: Group, from previous: EdgeLook?, to look: EdgeLook,
                           animated: Bool, switching: Bool) {
        let widthChange = abs((previous?.tubeWidth ?? look.tubeWidth) - look.tubeWidth)
        CATransaction.begin()
        if animated, !reduceMotion, !switching, look.isActive, widthChange >= Self.visibleChange {
            CATransaction.setAnimationDuration(0.45)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        switch part {
        case .edges:
            group.tubeMask.lineWidth = look.tubeWidth
            group.coreMask.lineWidth = look.coreWidth
            group.dots.lineWidth = look.particleDiameter
        case .marks:
            let path = chevronPath(for: look)
            group.halo.path = path
            group.ink.path = path
        }
        CATransaction.commit()
    }

    /// Partículas paradas no sítio, para a sonda de movimento medir só as transições.
    static var freezesParticles = false

    private func startParticles(_ group: Group, speed: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        group.particles.isHidden = false
        if Self.freezesParticles {
            group.dots.removeAnimation(forKey: Self.phaseKey)
            return
        }
        // Uma leitura nova mexe na velocidade por pouco. Só se troca a
        // animação quando a diferença se vê, e continua de onde ia.
        guard group.dots.animation(forKey: Self.phaseKey) == nil || abs(group.speed - speed) > 1 else { return }
        let phase = group.dots.presentation()?.lineDashPhase ?? 0
        let move = CABasicAnimation(keyPath: Self.phaseKey)
        move.fromValue = phase
        move.toValue = phase - Self.spacing
        move.duration = Self.spacing / speed
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        move.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        group.dots.add(move, forKey: Self.phaseKey)
        group.speed = speed
    }

    private func stopParticles(_ group: Group) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        group.dots.removeAnimation(forKey: Self.phaseKey)
        group.particles.isHidden = true
        group.speed = 0
        CATransaction.commit()
    }

    private func makeGroup(for edge: FlowEdgeKind, order: Int, in root: CALayer) -> Group {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let group = Group()
        group.root.frame = bounds
        group.root.zPosition = CGFloat(order)
        root.addSublayer(group.root)
        let curve = FlowLayout.curve(edge)

        switch part {
        case .edges:
            let path = edgePath(curve)

            group.track.frame = bounds
            group.track.path = path
            group.track.fillColor = nil
            group.track.strokeColor = resolved(PFColor.track)
            group.track.lineWidth = EdgeFlow.trackWidth
            group.track.lineCap = .round
            group.track.lineDashPattern = [3, 4]
            group.root.addSublayer(group.track)

            group.lit.frame = bounds
            group.root.addSublayer(group.lit)

            configure(group.tube, mask: group.tubeMask, path: path, curve: curve,
                      colors: [edge.from.color, edge.to.color], cap: .butt)
            group.tube.opacity = 0.28
            configure(group.core, mask: group.coreMask, path: path, curve: curve,
                      colors: [edge.from.color, edge.to.color], cap: .round)
            // As partículas levam as cores de tinta: com as do tubo confundiam-se com o núcleo.
            configure(group.particles, mask: group.dots, path: path, curve: curve,
                      colors: [edge.from.ink, edge.to.ink], cap: .round)
            group.dots.lineDashPattern = [0, NSNumber(value: Self.spacing)]
            group.particles.isHidden = true
            [group.tube, group.core, group.particles].forEach(group.lit.addSublayer)

        case .marks:
            let box = Self.chevronBox
            let center = chevronCenter(curve)
            group.chevron.bounds = CGRect(x: 0, y: 0, width: box, height: box)
            group.chevron.position = center
            for (shape, color, width) in [(group.halo, PFColor.bg, 5.5), (group.ink, edge.from.ink, 2.2)] {
                shape.frame = group.chevron.bounds
                shape.fillColor = nil
                shape.strokeColor = resolved(color)
                shape.lineWidth = width
                shape.lineCap = .round
                shape.lineJoin = .round
                group.chevron.addSublayer(shape)
            }
            group.root.addSublayer(group.chevron)

            let radius = FlowLayout.portRadius
            for (point, node) in [(curve.p0, edge.from), (curve.p3, edge.to)] {
                let port = CAShapeLayer()
                let center = flipped(point)
                port.frame = bounds
                port.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                     width: radius * 2, height: radius * 2), transform: nil)
                port.fillColor = resolved(PFColor.bg)
                port.lineWidth = 1.6
                group.root.addSublayer(port)
                group.ports.append((port, node))
            }
        }
        return group
    }

    private func configure(_ gradient: CAGradientLayer, mask: CAShapeLayer, path: CGPath,
                           curve: CubicCurve, colors: [Color], cap: CAShapeLayerLineCap) {
        mask.frame = bounds
        mask.path = path
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineCap = cap
        gradient.frame = bounds
        gradient.startPoint = unit(curve.p0)
        gradient.endPoint = unit(curve.p3)
        gradient.colors = colors.map(resolved)
        gradient.mask = mask
    }

    // MARK: - Geometria

    /// O SwiftUI conta o y de cima para baixo; uma camada do AppKit, de baixo
    /// para cima. A conversão faz-se aqui, ponto a ponto.
    private func flipped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / bounds.width, y: 1 - point.y / bounds.height)
    }

    private func edgePath(_ curve: CubicCurve) -> CGPath {
        let path = CGMutablePath()
        path.move(to: flipped(curve.p0))
        path.addCurve(to: flipped(curve.p3), control1: flipped(curve.p1), control2: flipped(curve.p2))
        return path
    }

    /// O centro do chevron: é à volta dele que cresce de 0,6 para 1.
    private func chevronCenter(_ curve: CubicCurve) -> CGPoint {
        let chevron = FlowLayout.chevron(on: curve, size: 6)
        return flipped(CGPoint(x: (chevron.start.x + chevron.tip.x + chevron.end.x) / 3,
                               y: (chevron.start.y + chevron.tip.y + chevron.end.y) / 3))
    }

    private func chevronPath(for look: EdgeLook) -> CGPath {
        let curve = FlowLayout.curve(look.edge)
        let chevron = FlowLayout.chevron(on: curve, size: look.chevronSize)
        let center = chevronCenter(curve)
        let half = Self.chevronBox / 2
        func local(_ point: CGPoint) -> CGPoint {
            let p = flipped(point)
            return CGPoint(x: p.x - center.x + half, y: p.y - center.y + half)
        }
        let path = CGMutablePath()
        path.move(to: local(chevron.start))
        path.addLine(to: local(chevron.tip))
        path.addLine(to: local(chevron.end))
        return path
    }

    private func resolved(_ color: Color) -> CGColor {
        var cg = NSColor.black.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cg = NSColor(color).cgColor
        }
        return cg
    }
}

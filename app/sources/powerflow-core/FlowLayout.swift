import CoreGraphics
import Foundation

public enum FlowNodeKind: Hashable, Sendable {
    case adapter, system, battery
}

public enum FlowEdgeKind: Hashable, Sendable, CaseIterable {
    case adapterToSystem, adapterToBattery, batteryToSystem

    public var from: FlowNodeKind {
        switch self {
        case .adapterToSystem, .adapterToBattery: return .adapter
        case .batteryToSystem: return .battery
        }
    }

    public var to: FlowNodeKind {
        switch self {
        case .adapterToSystem, .batteryToSystem: return .system
        case .adapterToBattery: return .battery
        }
    }
}

/// Uma Bézier cúbica, de porta a porta.
public struct CubicCurve: Equatable, Sendable {
    public let p0, p1, p2, p3: CGPoint

    public init(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
        self.p0 = p0; self.p1 = p1; self.p2 = p2; self.p3 = p3
    }

    public func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    /// A direção do caminho em `t`, com comprimento 1.
    public func tangent(at t: CGFloat) -> CGVector {
        let u = 1 - t
        let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
        let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
        let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

/// O chevron que marca o sentido de uma aresta: duas hastes que se juntam na ponta.
public struct FlowChevron: Equatable, Sendable {
    public let start: CGPoint
    public let tip: CGPoint
    public let end: CGPoint
}

/// A geometria do diagrama de fluxo. Coordenadas em pontos, com a origem no
/// canto superior esquerdo de uma área de 328 de largura. São os números do
/// handoff, sem escala: o painel tem sempre 360 pt.
public enum FlowLayout {
    public static let width: CGFloat = 328
    public static let nodeHeight: CGFloat = 48
    public static let portRadius: CGFloat = 3.2

    /// Sem bateria fica só a fila de cima.
    public static func height(hasBattery: Bool) -> CGFloat {
        hasBattery ? 136 : nodeHeight
    }

    public static func frame(of node: FlowNodeKind) -> CGRect {
        switch node {
        case .adapter: return CGRect(x: 0, y: 0, width: 112, height: nodeHeight)
        case .system:  return CGRect(x: 216, y: 0, width: 112, height: nodeHeight)
        case .battery: return CGRect(x: 94, y: 88, width: 140, height: nodeHeight)
        }
    }

    public static func nodes(hasBattery: Bool) -> [FlowNodeKind] {
        hasBattery ? [.adapter, .system, .battery] : [.adapter, .system]
    }

    public static func edges(hasBattery: Bool) -> [FlowEdgeKind] {
        hasBattery ? [.adapterToSystem, .adapterToBattery, .batteryToSystem] : [.adapterToSystem]
    }

    public static func curve(_ edge: FlowEdgeKind) -> CubicCurve {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        switch edge {
        case .adapterToSystem:  return CubicCurve(p(112, 24), p(148, 24), p(180, 24), p(216, 24))
        case .adapterToBattery: return CubicCurve(p(56, 48), p(56, 98), p(68, 112), p(94, 112))
        case .batteryToSystem:  return CubicCurve(p(234, 112), p(260, 112), p(272, 98), p(272, 48))
        }
    }

    /// O chevron a meio do caminho, apontado pela tangente.
    public static func chevron(on curve: CubicCurve, size s: CGFloat) -> FlowChevron {
        let c = curve.point(at: 0.5)
        let t = curve.tangent(at: 0.5)
        let n = CGVector(dx: -t.dy, dy: t.dx)
        let back = CGPoint(x: c.x - t.dx * s * 0.6, y: c.y - t.dy * s * 0.6)
        return FlowChevron(
            start: CGPoint(x: back.x + n.dx * s, y: back.y + n.dy * s),
            tip: CGPoint(x: c.x + t.dx * s * 0.5, y: c.y + t.dy * s * 0.5),
            end: CGPoint(x: back.x - n.dx * s, y: back.y - n.dy * s))
    }
}

extension PowerSnapshot {
    /// O caudal de cada aresta do diagrama, em watts.
    public func watts(on edge: FlowEdgeKind) -> Double {
        switch edge {
        case .adapterToSystem:  return adapterToSystem
        case .adapterToBattery: return adapterToBattery
        case .batteryToSystem:  return batteryToSystem
        }
    }
}

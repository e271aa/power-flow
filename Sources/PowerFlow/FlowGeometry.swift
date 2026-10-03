import SwiftUI

enum FlowNode: Hashable {
    case adapter, battery, system

    var title: String {
        switch self {
        case .adapter: return "Adaptador"
        case .battery: return "Bateria"
        case .system:  return "Sistema"
        }
    }

    var symbol: String {
        switch self {
        case .adapter: return "powerplug.fill"
        case .battery: return "battery.100"
        case .system:  return "cpu.fill"
        }
    }

    var tint: Color {
        switch self {
        case .adapter: return Color(red: 0.20, green: 0.78, blue: 0.45)
        case .battery: return Color(red: 0.98, green: 0.68, blue: 0.20)
        case .system:  return Color(red: 0.30, green: 0.62, blue: 0.98)
        }
    }
}

/// Uma aresta do diagrama, como Bézier quadrática.
///
/// Interpolamos os pontos à mão em vez de usar `Path.trimmedPath`: com
/// dezenas de partículas por fotograma, recortar o caminho a cada uma
/// seria o passo mais caro do desenho.
struct FlowEdge {
    let from: FlowNode
    let to: FlowNode
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

/// Posiciona os nós e constrói as arestas para um dado tamanho de tela.
struct FlowGeometry {
    let size: CGSize

    var nodeRadius: CGFloat {
        min(max(min(size.width, size.height) * 0.16, 26), 34)
    }

    func center(of node: FlowNode) -> CGPoint {
        switch node {
        case .adapter: return CGPoint(x: size.width * 0.18, y: size.height * 0.27)
        case .system:  return CGPoint(x: size.width * 0.82, y: size.height * 0.27)
        case .battery: return CGPoint(x: size.width * 0.50, y: size.height * 0.78)
        }
    }

    /// Encosta o extremo da aresta à borda do nó, para a linha não entrar
    /// por baixo do círculo.
    private func trim(_ point: CGPoint, towards control: CGPoint) -> CGPoint {
        let dx = control.x - point.x
        let dy = control.y - point.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let inset = nodeRadius + 4
        return CGPoint(x: point.x + dx / length * inset, y: point.y + dy / length * inset)
    }

    func edge(from: FlowNode, to: FlowNode) -> FlowEdge {
        let a = center(of: from)
        let b = center(of: to)

        let control: CGPoint
        switch (from, to) {
        case (.adapter, .system):
            // Arco suave por cima, para não colidir com os outros dois ramos.
            control = CGPoint(x: (a.x + b.x) / 2, y: a.y - size.height * 0.16)
        case (.adapter, .battery):
            // Arco suave para fora, em vez do cotovelo que um ponto de
            // controlo no canto produzia.
            control = CGPoint(x: (a.x + b.x) / 2 - size.width * 0.10,
                              y: (a.y + b.y) / 2 + size.height * 0.14)
        case (.battery, .system):
            control = CGPoint(x: (a.x + b.x) / 2 + size.width * 0.10,
                              y: (a.y + b.y) / 2 + size.height * 0.14)
        default:
            control = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        return FlowEdge(from: from, to: to,
                        start: trim(a, towards: control),
                        control: control,
                        end: trim(b, towards: control))
    }
}

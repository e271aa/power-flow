import Foundation

/// Uma aresta acesa só se apaga depois de 1 s seguido abaixo do limiar.
///
/// Um caudal perto dos 0,15 W passa o limiar para um lado e para o outro de
/// leitura para leitura, e a aresta piscava. Acender é imediato; apagar
/// espera (handoff, «Movimento»: «o desaparecimento espera 1 s de estabilidade»).
public struct EdgeHold: Equatable, Sendable {
    public static let release: TimeInterval = 1
    /// As publicações são de 1 Hz e o temporizador não é exato: 0,98 s também é «1 s».
    private static let tolerance: TimeInterval = 0.05

    private var lit: Set<FlowEdgeKind> = []
    /// Desde quando cada aresta acesa está abaixo do limiar.
    private var belowSince: [FlowEdgeKind: Date] = [:]

    public init() {}

    /// As arestas que se mostram acesas, dadas as que estão acima do limiar agora.
    public mutating func update(active: Set<FlowEdgeKind>, at now: Date) -> Set<FlowEdgeKind> {
        for edge in FlowEdgeKind.allCases {
            if active.contains(edge) {
                lit.insert(edge)
                belowSince[edge] = nil
            } else if lit.contains(edge) {
                let since = belowSince[edge] ?? now
                if now.timeIntervalSince(since) >= Self.release - Self.tolerance {
                    lit.remove(edge)
                    belowSince[edge] = nil
                } else {
                    belowSince[edge] = since
                }
            }
        }
        return lit
    }

    /// As arestas que ficam acesas só por estarem à espera: já abaixo do limiar.
    public mutating func held(for snapshot: PowerSnapshot, at now: Date) -> Set<FlowEdgeKind> {
        let active = Set(FlowEdgeKind.allCases.filter { snapshot.watts(on: $0) > PanelState.edgeThreshold })
        return update(active: active, at: now).subtracting(active)
    }
}

/// O intervalo mínimo entre duas publicações para a interface.
///
/// O monitor publica a 1 Hz e também quando o sistema avisa de uma mudança na
/// fonte de energia; as duas coisas juntas chegaram a dar três publicações
/// no mesmo segundo. Os números só podem mudar 2 vezes por segundo (handoff).
public struct PublishGate: Equatable, Sendable {
    public static let minimumInterval: TimeInterval = 0.5

    private var last: Date?

    public init() {}

    /// Quanto falta esperar até se poder publicar. Zero: pode já.
    public func wait(at now: Date) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, Self.minimumInterval - now.timeIntervalSince(last))
    }

    public mutating func published(at now: Date) {
        last = now
    }
}

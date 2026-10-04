import Foundation

/// O aspeto de uma aresta do diagrama para o caudal que a atravessa.
///
/// Espessura, número, velocidade e tamanho crescem com o caudal, mas em raiz
/// quadrada: entre 1 W e 60 W a diferença linear seria tão grande que os
/// caudais pequenos ficariam invisíveis.
public struct EdgeFlow: Equatable, Sendable {
    public let watts: Double
    /// Abaixo do limiar a aresta desenha-se apagada e sem partículas.
    public let isActive: Bool
    public let lineWidth: Double
    /// Zero sem caudal e com Reduzir Movimento: a espessura e a cor dizem o
    /// mesmo que as partículas, por isso nada essencial se perde.
    public let particleCount: Int
    /// Voltas ao caminho por segundo.
    public let particleSpeed: Double
    public let particleRadius: Double

    public init(watts: Double, reduceMotion: Bool) {
        self.watts = watts
        isActive = watts > PanelState.edgeThreshold

        let scaled = min(sqrt(max(watts, 0)) / sqrt(60), 1)
        lineWidth = isActive ? 2 + scaled * 4 : 2
        particleCount = isActive && !reduceMotion ? 3 + Int(scaled * 9) : 0
        particleSpeed = 0.10 + scaled * 0.45
        particleRadius = 1.8 + scaled * 2.2
    }
}

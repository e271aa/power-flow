import Foundation

/// O aspeto de uma aresta do diagrama para o caudal que a atravessa.
///
/// As fórmulas são as do handoff («Diagrama de fluxo»). A espessura cresce
/// com a raiz quadrada do caudal: entre 1 W e 70 W a diferença linear seria
/// tão grande que os caudais pequenos ficariam invisíveis.
public struct EdgeFlow: Equatable, Sendable {
    /// Espessura do trilho tracejado de uma aresta sem caudal.
    public static let trackWidth: Double = 1.5
    /// Distância entre partículas, ao longo do caminho.
    public static let particleSpacing: Double = 14
    /// Caudal a partir do qual a espessura deixa de crescer.
    private static let fullScale: Double = 70

    public let watts: Double
    /// Abaixo do limiar, ou durante a estabilização, a aresta é só o trilho.
    public let isActive: Bool
    /// Espessura do tubo, a 28 % de opacidade.
    public let tubeWidth: Double
    /// Espessura do núcleo, opaco.
    public let coreWidth: Double
    /// Tamanho do chevron que marca o sentido.
    public let chevronSize: Double
    /// Falso sem caudal e com Reduzir Movimento: a espessura e o chevron
    /// dizem o mesmo que as partículas, por isso nada essencial se perde.
    public let hasParticles: Bool
    public let particleDiameter: Double
    /// Pontos por segundo ao longo do caminho.
    public let particleSpeed: Double

    /// `isSuppressed`: o painel ainda está a estabilizar e nenhum caudal é de confiança.
    public init(watts: Double, isSuppressed: Bool = false, reduceMotion: Bool) {
        self.watts = watts
        isActive = watts > PanelState.edgeThreshold && !isSuppressed

        let k = sqrt(min(max(watts, 0), Self.fullScale) / Self.fullScale)
        tubeWidth = 2.5 + 9 * k
        coreWidth = 1.6 + 0.12 * tubeWidth
        chevronSize = 3.6 + 0.3 * tubeWidth
        hasParticles = isActive && !reduceMotion
        // O handoff dá max(3, 0,55·sw). Ao vivo, com 10 a 20 W, os pontos mal
        // passavam da largura do núcleo e quase não se viam.
        particleDiameter = max(4, 0.7 * tubeWidth)
        particleSpeed = 14 + 46 * k
    }
}

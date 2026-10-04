import Foundation

/// Duas médias móveis sobre a mesma janela de tempo, uma por ritmo.
///
/// Com o painel fechado a app só lê o SMC a 1 Hz; com ele aberto lê a 10 Hz.
/// O `PowerSmoother` conta amostras e não segundos, por isso cada ritmo tem
/// a sua média: três amostras a 1 Hz e trinta a 10 Hz cobrem os mesmos três
/// segundos, e o recuo do adaptador (uma amostra e dez) cobre o mesmo
/// segundo de atraso.
///
/// O recuo é de 1,0 s. Medido com a carga parada e rajadas de CPU de 10 W
/// para 39 W: com dez amostras de recuo a 10 Hz a entrada e o consumo
/// coincidem ao centésimo em todas as leituras; com nove ou com onze, a
/// diferença chega a 1,1 W em cada rampa (uma amostra de desalinhamento).
///
/// A média lenta nunca pára. É ela que responde enquanto a rápida enche,
/// para abrir o painel não o pôr «a estabilizar» outra vez.
///
/// Mas a 1 Hz o alinhamento não é de confiança. Os dois registos atualizam
/// uma vez por segundo, e uma amostra que caia entre a atualização de um e
/// a do outro falha o recuo por um segundo inteiro: medido, até 9,5 W de
/// diferença numa rampa de carga. A 10 Hz o mesmo azar custa um décimo
/// disso. Por isso só a média rápida se dá como alinhada.
public struct DualRateSmoother {
    private var slow = PowerSmoother(windowSize: 3, adapterDelay: 1)
    private var fast = DualRateSmoother.makeFast()

    private static func makeFast() -> PowerSmoother {
        PowerSmoother(windowSize: 30, adapterDelay: 10)
    }

    public private(set) var isFast = false

    public init() {}

    /// Liga ou desliga o ritmo rápido. Ao desligar, a média rápida é deitada
    /// fora: quando voltar a ligar, o que lá estava já não é recente.
    public mutating func setFast(_ on: Bool) {
        guard on != isFast else { return }
        isFast = on
        fast = Self.makeFast()
    }

    /// Ligar ou desligar o cabo muda o que a entrada mede de um instante
    /// para o outro. As leituras de antes já não se comparam com as de
    /// agora: logo depois de ligar o cabo, a janela ainda tem os zeros de
    /// quando estava desligado, e a diferença para o consumo lia-se como a
    /// bateria a ajudar (medido: até 16 W durante 4 s). A média rápida
    /// recomeça, e até encher não há alinhamento.
    public mutating func sourceChanged() {
        fast = Self.makeFast()
    }

    /// Uma leitura do ritmo de 1 Hz. Chama-se sempre, aberto ou fechado.
    public mutating func addSlow(_ reading: RailReading) {
        slow.add(reading)
    }

    /// Uma leitura do ritmo de 10 Hz.
    public mutating func addFast(_ reading: RailReading) {
        fast.add(reading)
    }

    private var usesFast: Bool { isFast && fast.isAligned }

    public var average: RailReading {
        usesFast ? fast.average : slow.average
    }

    /// Já há leituras que cheguem para mostrar números.
    public var isSettled: Bool {
        usesFast || slow.isAligned
    }

    /// A entrada e o consumo estão alinhados no tempo, e a diferença entre
    /// eles pode ler-se como assistência da bateria.
    public var isAligned: Bool {
        usesFast
    }
}

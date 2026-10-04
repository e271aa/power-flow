import Foundation

/// Média móvel sobre as leituras do SMC, com alinhamento temporal entre elas.
///
/// O `PSTR` (consumo) está atrasado 1,0 s face ao `PDTR` (entrada).
/// A primeira medição, por correlação cruzada entre as duas séries a 10 Hz
/// durante 40 s, deu 0.9 s (r = 0.9926, contra r = 0.66 sem desfasamento).
/// A segunda, com degraus de carga e os recuos de 9, 10 e 11 amostras lado
/// a lado, mostrou que só com 10 as duas séries coincidem.
/// Não são grandezas diferentes a discordar — é a mesma grandeza, com um dos
/// registos a atualizar mais tarde.
///
/// Comparar as duas sem alinhar produzia caudais inventados: quando a entrada
/// descia, o consumo ainda reportava o valor antigo, mais alto, e a diferença
/// aparecia como assistência da bateria que nunca existiu. Ao subir, sumia
/// energia. Era isso, e não física, que fazia a seta da bateria piscar com o
/// carregador ligado.
///
/// A correção é comparar cada leitura com a contemporânea: a janela do
/// adaptador recua `adapterDelay` amostras para coincidir com o instante a
/// que o consumo se refere.
public struct PowerSmoother {
    /// Amostras na janela de média. A 10 Hz, 30 amostras são três segundos.
    public let windowSize: Int
    /// Quantas amostras recuar a janela do adaptador. A 10 Hz, 10 são 1,0 s.
    public let adapterDelay: Int

    private var samples: [RailReading] = []
    private var capacity: Int { windowSize + adapterDelay }

    public init(windowSize: Int = 30, adapterDelay: Int = 10) {
        self.windowSize = max(1, windowSize)
        self.adapterDelay = max(0, adapterDelay)
    }

    /// Verdadeiro quando já há amostras suficientes para a janela do
    /// adaptador estar de facto recuada. Antes disso as duas leituras ainda
    /// não estão alinhadas e a diferença entre elas não significa nada.
    public var isAligned: Bool { samples.count >= capacity }

    @discardableResult
    public mutating func add(_ reading: RailReading) -> RailReading {
        samples.append(reading)
        if samples.count > capacity { samples.removeFirst() }
        return average
    }

    public var average: RailReading {
        let recent = Array(samples.suffix(windowSize))

        // Só recua se já houver histórico para isso; no arranque usa o que tem,
        // à custa de algum desalinhamento nos primeiros instantes.
        let aligned = samples.count > adapterDelay
            ? Array(samples.dropLast(adapterDelay).suffix(windowSize))
            : recent

        var result = RailReading()
        result.systemTotal = mean(recent, \.systemTotal)
        result.socPower = mean(recent, \.socPower)
        result.mainRailPower = mean(recent, \.mainRailPower)
        result.batteryTemperature = mean(recent, \.batteryTemperature)
        result.adapterInput = mean(aligned, \.adapterInput)
        return result
    }

    /// Ignora as leituras em falta: uma chave que não exista neste Mac não
    /// deve arrastar a média para baixo como se fosse zero.
    private func mean(_ window: [RailReading],
                      _ key: KeyPath<RailReading, Double?>) -> Double? {
        let values = window.compactMap { $0[keyPath: key] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

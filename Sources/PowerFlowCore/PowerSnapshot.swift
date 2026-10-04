import Foundation

public enum PowerSource: Sendable {
    case adapter
    case battery
}

/// Um instantâneo completo do estado energético da máquina.
public struct PowerSnapshot: Sendable {
    public var timestamp: Date = Date()
    public var battery = BatteryInfo()

    public var adapterInput: Double?        // W a entrar pelo adaptador
    public var systemTotal: Double?         // W consumidos pelo sistema
    public var socPower: Double?            // W do CPU+GPU+ANE
    public var mainRailPower: Double?       // W do ecrã/SSD/I-O
    public var batteryTemperature: Double?  // graus C

    /// Magnitude da potência que atravessa a bateria, sempre >= 0.
    /// O sentido vem de `source` e `battery.isCharging`, não do sinal.
    public var batteryMagnitude: Double = 0

    /// Falso durante os primeiros segundos, enquanto a média móvel enche.
    /// Nesse intervalo a entrada e o consumo ainda não estão alinhados no
    /// tempo, e a diferença entre eles é ruído de arranque, não assistência.
    public var isAligned: Bool = true

    /// Falso só no arranque, enquanto ainda não há leituras que cheguem
    /// para mostrar números. Não é o mesmo que `isAligned`: com o painel
    /// fechado, a 1 Hz, há números mas a diferença entre entrada e consumo
    /// não é de confiança.
    public var isSettled: Bool = true

    /// Segundos que faltam para `isSettled`. Zero depois de estabilizar.
    public var settleRemaining: Double = 0

    public init() {}

    /// Um Mac sem bateria está sempre ligado à corrente. Sem esta guarda, a
    /// falta de `ExternalConnected` punha a energia a sair de uma bateria
    /// que não existe.
    public var source: PowerSource {
        guard battery.isPresent else { return .adapter }
        return battery.isExternalConnected ? .adapter : .battery
    }

    // MARK: - Caudais do diagrama

    /// O balanço do diagrama sai da diferenca entre a entrada do adaptador e
    /// o consumo do sistema, ambos lidos do SMC no mesmo instante.
    ///
    /// A alternativa - usar V x A da bateria para o ramo da carga - nao
    /// fecha: medido com o CPU saturado, o adaptador dava 65.2 W, o sistema
    /// consumia 35.9 W e o IORegistry ainda reportava 39.2 W a entrar na
    /// bateria, um total de 75 W que nao existe. A corrente da bateria no
    /// IORegistry atualiza devagar e fica para tras quando o carregador
    /// reduz a carga para alimentar o sistema. V x A fica como recurso para
    /// quando o SMC nao expoe o consumo total.

    /// W que vão do adaptador diretamente para o sistema.
    public var adapterToSystem: Double {
        guard source == .adapter else { return 0 }
        // Sem bateria não há outro caminho: tudo o que o sistema consome
        // vem da corrente, haja ou não leitura da entrada.
        guard battery.isPresent else { return systemTotal ?? adapterInput ?? 0 }
        guard let input = adapterInput else { return 0 }
        guard let total = systemTotal else { return max(0, input - adapterToBattery) }
        return min(input, total)
    }

    /// W que vão do adaptador para carregar a bateria.
    public var adapterToBattery: Double {
        guard source == .adapter, battery.isCharging else { return 0 }
        guard let input = adapterInput, let total = systemTotal else {
            return batteryMagnitude
        }
        return max(0, input - total)
    }

    /// W que saem da bateria para o sistema.
    ///
    /// Acontece com o cabo desligado, mas também com o cabo ligado quando o
    /// sistema pede mais do que o adaptador consegue dar.
    public var batteryToSystem: Double {
        guard battery.isPresent else { return 0 }
        switch source {
        case .battery:
            return systemTotal ?? batteryMagnitude
        case .adapter:
            guard isAligned,
                  let total = systemTotal, let input = adapterInput,
                  total > input + Self.assistTolerance
            else { return 0 }
            return total - input
        }
    }

    /// Margem abaixo da qual a diferença entre consumo e entrada é ruído de
    /// amostragem e não assistência real da bateria.
    public static let assistTolerance: Double = 1.5

    /// Substitui as leituras de rails, mantendo o estado da bateria.
    public mutating func apply(_ reading: RailReading) {
        adapterInput = reading.adapterInput
        systemTotal = reading.systemTotal
        socPower = reading.socPower
        mainRailPower = reading.mainRailPower
        batteryTemperature = reading.batteryTemperature
    }

    /// Repartição do consumo do sistema que não é atribuível ao SoC nem ao
    /// rail principal. `nil` quando não há dados suficientes.
    public var otherPower: Double? {
        guard let total = systemTotal, let soc = socPower else { return nil }
        let accounted = soc + (mainRailPower ?? 0)
        return max(0, total - accounted)
    }
}

/// Só as leituras do SMC, sem tocar no IORegistry.
///
/// Existe separada porque é barata: são chamadas IOKit diretas, que se podem
/// repetir várias vezes por segundo. A leitura da bateria, essa, constrói um
/// dicionário inteiro de propriedades e não deve ser feita ao mesmo ritmo.
public struct RailReading: Sendable {
    public var adapterInput: Double?
    public var systemTotal: Double?
    public var socPower: Double?
    public var mainRailPower: Double?
    public var batteryTemperature: Double?

    public init() {}
}

/// Junta SMC e IORegistry num instantâneo.
public enum PowerSampler {
    /// Leitura rápida, só do SMC.
    public static func sampleRails() -> RailReading {
        let catalog = SMCCatalog.shared
        var reading = RailReading()
        reading.adapterInput = catalog.watts(.adapterInput)
        reading.systemTotal = catalog.watts(.systemTotal)
        reading.socPower = catalog.watts(.soc)
        reading.mainRailPower = catalog.watts(.mainRail)
        reading.batteryTemperature = catalog.celsius(.battery)
        return reading
    }

    public static func sample() -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        snapshot.battery = BatteryReader.read()
        snapshot.apply(PowerSampler.sampleRails())

        // A potência da bateria vem do IORegistry, nao do SMC.
        //
        // O SMC tem uma chave PPBR que parece ser isto e nao e: medida num
        // M1 Pro, marcou 0.96 W tanto com a bateria parada como a carregar a
        // 3.9 A. Nenhuma das 2179 chaves acompanha a carga real. V x A do
        // IORegistry reconcilia com a entrada do adaptador: 65.1 W a entrar
        // menos 18.4 W de sistema sao 46.7 W, contra 48.5 W de V x A.
        let info = snapshot.battery
        snapshot.batteryMagnitude = abs(info.voltage * info.amperage)

        return snapshot
    }
}

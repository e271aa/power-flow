import Foundation

/// As grandezas de potência que o diagrama precisa, cada uma mapeada para
/// uma lista de chaves SMC candidatas.
///
/// Os nomes das chaves não são documentados pela Apple e variam entre
/// gerações de chip. A primeira candidata que existir neste Mac é a que
/// fica a valer; se nenhuma existir, a grandeza fica `nil` e a UI
/// simplesmente não mostra essa parte do diagrama.
///
/// Valores confirmados num M1 Pro por correlação contra carga de CPU real:
/// em repouso vs. 8 processos a saturar o CPU, PSTR 8.84 -> 36.09 W,
/// PDTR 9.88 -> 34.32 W, PSVR 2.06 -> 23.86 W, PMVR 4.79 -> 5.90 W.
public enum PowerRail: String, CaseIterable, Sendable {
    /// Potência total consumida pelo sistema.
    case systemTotal
    /// Potência a entrar pelo adaptador (DC in).
    case adapterInput
    /// Rail que alimenta o SoC. Segue a carga de CPU 1:1.
    ///
    /// Nao e o mesmo que a soma CPU+GPU+ANE do powermetrics: medido em
    /// simultaneo sob carga estavel, o PSVR deu 26.62 W contra 22.86 W do
    /// powermetrics, +16.4 %. A diferenca e esperada e nao e erro — o
    /// powermetrics estima potencia ao nivel do die para tres blocos, o PSVR
    /// mede o rail inteiro, incluindo controlador de memoria, fabric, cache
    /// de sistema e perdas do regulador. Para um diagrama de fluxo o rail e
    /// o numero certo: e o que sai da bateria.
    case soc
    /// Rail principal: ecrã, SSD, I/O. Quase insensível a carga de CPU.
    case mainRail

    var candidates: [String] {
        switch self {
        case .systemTotal:  return ["PSTR"]
        case .adapterInput: return ["PDTR", "PZ0R"]
        case .soc:          return ["PSVR", "PHPS", "PZC0"]
        case .mainRail:     return ["PMVR", "PMVC"]
        }
    }
}

/// Temperaturas de interesse, com a mesma lógica de candidatas.
public enum TemperatureSensor: String, CaseIterable, Sendable {
    case battery

    var candidates: [String] {
        switch self {
        case .battery: return ["TB0T", "TB1T"]
        }
    }
}

/// Resolve uma vez, no arranque, que chave serve cada grandeza neste Mac.
public final class SMCCatalog {
    public static let shared = SMCCatalog()

    private let smc = SMC.shared
    private var railKeys: [PowerRail: String] = [:]
    private var tempKeys: [TemperatureSensor: String] = [:]
    public private(set) var isAvailable = false

    private init() {}

    /// Abre o SMC e descobre as chaves disponíveis. Idempotente.
    @discardableResult
    public func prepare() -> Bool {
        guard smc.open() else { return false }
        if isAvailable { return true }

        for rail in PowerRail.allCases {
            if let key = rail.candidates.first(where: { smc.read($0) != nil }) {
                railKeys[rail] = key
            }
        }
        for sensor in TemperatureSensor.allCases {
            if let key = sensor.candidates.first(where: { smc.read($0) != nil }) {
                tempKeys[sensor] = key
            }
        }

        // Sem estas duas não há diagrama de fluxo nenhum que valha a pena.
        isAvailable = railKeys[.systemTotal] != nil || railKeys[.adapterInput] != nil
        return isAvailable
    }

    public func watts(_ rail: PowerRail) -> Double? {
        guard let key = railKeys[rail] else { return nil }
        return smc.read(key)
    }

    public func celsius(_ sensor: TemperatureSensor) -> Double? {
        guard let key = tempKeys[sensor] else { return nil }
        return smc.read(key)
    }

    /// Que chave ficou a servir cada grandeza — aparece no `--dump`.
    public func resolvedKey(for rail: PowerRail) -> String? { railKeys[rail] }
}

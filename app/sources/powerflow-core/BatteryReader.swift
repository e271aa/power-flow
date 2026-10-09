import Foundation
import IOKit

/// Estado da bateria e do adaptador, lido do IORegistry.
///
/// Complementa o SMC: o SMC dá os watts instantâneos, o IORegistry dá o
/// contexto (ciclos, saúde, que adaptador está ligado, porque é que não
/// está a carregar).
public struct BatteryInfo: Sendable {
    public var isPresent: Bool = false
    public var percentage: Int = 0
    public var isCharging: Bool = false
    public var isExternalConnected: Bool = false
    public var isFullyCharged: Bool = false

    public var voltage: Double = 0          // volts
    public var amperage: Double = 0         // amperes, positivo a carregar
    public var cycleCount: Int = 0

    public var currentCapacity: Int = 0     // mAh
    public var fullChargeCapacity: Int = 0  // mAh
    public var designCapacity: Int = 0      // mAh

    public var adapterWatts: Int = 0
    public var adapterName: String = ""
    public var notChargingReason: Int = 0
    public var minutesRemaining: Int? = nil

    public init() {}

    /// Saúde: capacidade máxima atual face à de fábrica.
    public var healthPercent: Double? {
        guard designCapacity > 0, fullChargeCapacity > 0 else { return nil }
        return Double(fullChargeCapacity) / Double(designCapacity) * 100
    }

    /// Tradução legível do `NotChargingReason`, que de outra forma é um
    /// inteiro opaco. Muito mais útil do que um simples "não está a carregar".
    public var chargingExplanation: String? {
        guard isExternalConnected, !isCharging, !isFullyCharged else { return nil }
        switch notChargingReason {
        case 0:         return nil
        case 1:         return "Bateria cheia"
        case 16:        return "Pausado por temperatura"
        case 128:       return "Em espera"
        case 1024:      return "Adaptador sem potência suficiente"
        case 16777216:  return "Carga otimizada da Apple"
        default:        return "Em pausa (código \(notChargingReason))"
        }
    }
}

public enum BatteryReader {
    /// Lê o estado atual. Devolve `isPresent == false` num Mac sem bateria.
    public static func read() -> BatteryInfo {
        var info = BatteryInfo()

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return info }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return info }

        info.isPresent = props["BatteryInstalled"] as? Bool ?? false
        info.isCharging = props["IsCharging"] as? Bool ?? false
        info.isExternalConnected = props["ExternalConnected"] as? Bool ?? false
        info.isFullyCharged = props["FullyCharged"] as? Bool ?? false
        info.cycleCount = props["CycleCount"] as? Int ?? 0

        // Milivolts e miliamperes no registo; a app trabalha em V e A.
        info.voltage = Double(props["Voltage"] as? Int ?? 0) / 1000.0
        info.amperage = Double(props["Amperage"] as? Int ?? 0) / 1000.0

        // Em Apple Silicon a percentagem e as capacidades vivem num
        // sub-dicionário; os campos de topo são legados.
        if let data = props["BatteryData"] as? [String: Any] {
            info.percentage = data["CurrentCapacity"] as? Int ?? 0
            info.currentCapacity = data["RemainingCapacity"] as? Int ?? 0
            info.fullChargeCapacity = data["FullChargeCapacity"] as? Int ?? 0
            info.designCapacity = data["DesignCapacity"] as? Int ?? 0
        }
        if info.percentage == 0 { info.percentage = props["CurrentCapacity"] as? Int ?? 0 }

        if let charger = props["ChargerData"] as? [String: Any] {
            info.notChargingReason = charger["NotChargingReason"] as? Int ?? 0
        }

        if let adapter = props["AdapterDetails"] as? [String: Any] {
            info.adapterWatts = adapter["Watts"] as? Int ?? 0
            info.adapterName = adapter["Name"] as? String ?? ""
        }

        // 65535 é o valor-sentinela para "ainda a calcular".
        if let remaining = props["TimeRemaining"] as? Int, remaining != 65535, remaining > 0 {
            info.minutesRemaining = remaining
        }

        return info
    }
}

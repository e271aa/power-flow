import Foundation

/// Modo de diagnóstico da linha de comandos.
///
/// Existe para responder a "que chaves é que este Mac tem?" sem abrir a UI.
/// É a ferramenta a usar quando alguém com um chip diferente reporta que o
/// diagrama aparece incompleto.
public enum Diagnostics {
    public static func dump() {
        guard SMCCatalog.shared.prepare() else {
            print("Não foi possível abrir o AppleSMC.")
            return
        }

        let snapshot = PowerSampler.sample()

        print("== Chaves resolvidas ==")
        for rail in PowerRail.allCases {
            let key = SMCCatalog.shared.resolvedKey(for: rail) ?? "—"
            let value = SMCCatalog.shared.watts(rail)
            let shown = value.map { String(format: "%8.3f W", $0) } ?? "     n/d"
            print(String(format: "  %-14s %-6s %@", (rail.rawValue as NSString).utf8String!,
                         (key as NSString).utf8String!, shown))
        }

        print("\n== Fluxo ==")
        print(String(format: "  fonte                %@", snapshot.source == .adapter ? "adaptador" : "bateria"))
        print(String(format: "  adaptador -> sistema %8.3f W", snapshot.adapterToSystem))
        print(String(format: "  adaptador -> bateria %8.3f W", snapshot.adapterToBattery))
        print(String(format: "  bateria   -> sistema %8.3f W", snapshot.batteryToSystem))
        if let other = snapshot.otherPower {
            print(String(format: "  outros (resto)       %8.3f W", other))
        }

        let battery = snapshot.battery
        print("\n== Bateria ==")
        print("  carga                \(battery.percentage) %")
        print("  ciclos               \(battery.cycleCount)")
        if let health = battery.healthPercent {
            print(String(format: "  saúde                %.1f %% (%d / %d mAh)",
                         health, battery.fullChargeCapacity, battery.designCapacity))
        }
        print(String(format: "  tensão               %.3f V", battery.voltage))
        print(String(format: "  corrente             %.3f A", battery.amperage))
        if let temp = snapshot.batteryTemperature {
            print(String(format: "  temperatura          %.1f °C", temp))
        }
        if !battery.adapterName.isEmpty {
            print("  adaptador            \(battery.adapterName) (\(battery.adapterWatts) W)")
        }
        if let why = battery.chargingExplanation {
            print("  não carrega porquê   \(why)")
        }
    }

    /// Todas as chaves de potência em bruto, para investigação.
    public static func dumpAllPowerKeys() {
        guard SMC.shared.open() else { print("SMC indisponível."); return }
        for key in SMC.shared.allKeys() where key.hasPrefix("P") {
            guard let value = SMC.shared.read(key) else { continue }
            let type = SMC.shared.type(of: key) ?? "?"
            print(String(format: "%-5s %-5s %12.4f",
                         (key as NSString).utf8String!, (type as NSString).utf8String!, value))
        }
    }
}

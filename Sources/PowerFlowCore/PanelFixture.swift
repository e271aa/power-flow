import Foundation

/// Os nove estados do painel com os números do protótipo do handoff.
///
/// Servem o `--snapshot --state …`, para comparar a app com o protótipo lado
/// a lado, e os testes dos textos. Não tocam no hardware.
public enum PanelFixture: String, CaseIterable, Sendable {
    case charging, optimized, temperature, weak, assist, battery, nobattery, unavailable, warming

    public var sensorsAvailable: Bool { self != .unavailable }

    public var snapshot: PowerSnapshot {
        var s = PowerSnapshot()
        s.battery.isPresent = true
        s.battery.isExternalConnected = true
        s.battery.adapterWatts = 67
        s.battery.adapterName = "USB-C"
        s.battery.percentage = 80
        s.batteryTemperature = 28

        func rails(adapter: Double?, system: Double, soc: Double, main: Double) {
            s.adapterInput = adapter
            s.systemTotal = system
            s.socPower = soc
            s.mainRailPower = main
        }
        func paused(reason: Int, percent: Int, temperature: Double) {
            s.battery.notChargingReason = reason
            s.battery.percentage = percent
            s.batteryTemperature = temperature
        }

        switch self {
        case .charging:
            rails(adapter: 65.0, system: 36.1, soc: 24.0, main: 5.9)
            s.battery.isCharging = true
            s.battery.percentage = 52
            s.battery.minutesRemaining = 65
            s.batteryTemperature = 31.4
        case .optimized:
            rails(adapter: 9.8, system: 9.8, soc: 1.6, main: 3.3)
            paused(reason: 16_777_216, percent: 80, temperature: 27.2)
        case .temperature:
            rails(adapter: 22.4, system: 22.4, soc: 13.1, main: 5.4)
            paused(reason: 16, percent: 64, temperature: 41.3)
        case .weak:
            rails(adapter: 18.7, system: 18.7, soc: 9.6, main: 5.2)
            paused(reason: 1024, percent: 38, temperature: 29.0)
            s.battery.adapterWatts = 20
        case .assist:
            rails(adapter: 29.6, system: 41.8, soc: 30.2, main: 6.1)
            s.battery.adapterWatts = 30
            s.battery.percentage = 71
            s.batteryTemperature = 33.5
        case .battery:
            rails(adapter: nil, system: 9.4, soc: 2.2, main: 4.6)
            s.battery.isExternalConnected = false
            s.battery.adapterWatts = 0
            s.battery.adapterName = ""
            s.battery.percentage = 74
            s.battery.minutesRemaining = 340
            s.batteryTemperature = 28.1
        case .nobattery:
            rails(adapter: 14.2, system: 14.2, soc: 6.1, main: 3.0)
            s.battery = BatteryInfo()
            s.batteryTemperature = nil
        case .unavailable:
            paused(reason: 16_777_216, percent: 80, temperature: 27.2)
        case .warming:
            rails(adapter: 12.4, system: 10.1, soc: 2.6, main: 4.1)
            paused(reason: 16_777_216, percent: 80, temperature: 27.2)
            s.isSettled = false
            s.isAligned = false
            s.settleRemaining = 3
        }
        return s
    }

    public var panel: PanelState {
        PanelState(snapshot: snapshot, sensorsAvailable: sensorsAvailable)
    }

    /// Dois minutos de histórico à volta do consumo do estado, sempre iguais.
    public var history: [PowerHistory.Sample] {
        let snapshot = self.snapshot
        guard sensorsAvailable, let system = snapshot.systemTotal else { return [] }
        var seed: UInt32 = 7
        for byte in rawValue.utf8 { seed = seed &* 31 &+ UInt32(byte) }
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed) / 4_294_967_296
        }
        let flow = snapshot.adapterToBattery - snapshot.batteryToSystem
        let raw = (0..<120).map { _ in system * (0.9 + 0.2 * random()) }
        return raw.indices.map { i in
            let around = raw[max(0, i - 1)...min(raw.count - 1, i + 1)]
            return PowerHistory.Sample(
                timestamp: snapshot.timestamp.addingTimeInterval(Double(i - 119)),
                systemTotal: around.reduce(0, +) / Double(around.count),
                adapterInput: snapshot.adapterInput ?? 0,
                batteryFlow: flow)
        }
    }
}

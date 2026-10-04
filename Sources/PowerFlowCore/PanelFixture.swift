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
}

extension PanelFixture {
    /// O histórico do estado nos três períodos, com os mesmos números que o
    /// protótipo gera: o mesmo gerador, a mesma semente.
    ///
    /// `fresh`: só os últimos 18 min, como nos primeiros minutos depois de instalar.
    public func history(fresh: Bool = false, now: Date) -> HistoryStore {
        let store = HistoryStore()
        guard sensorsAvailable else { return store }
        for period in HistoryPeriod.allCases {
            let n = period.slots
            let last = Int((now.timeIntervalSince1970 / period.resolution).rounded(.down))
            let values = generated(period, fresh: fresh)
            let points: [HistoryPoint] = values.enumerated().compactMap { index, value in
                guard let value else { return nil }
                let bucket = last - (n - 1 - index)
                return HistoryPoint(t: Date(timeIntervalSince1970: Double(bucket) * period.resolution),
                                    system: value.system, adapter: value.adapter)
            }
            store.seed(points, for: period)
        }
        return store
    }

    private func generated(_ period: HistoryPeriod, fresh: Bool) -> [(system: Double, adapter: Double?)?] {
        let snapshot = self.snapshot
        let key = rawValue
        let n = period.slots
        let system = snapshot.systemTotal ?? 0
        let input = snapshot.adapterInput ?? 0
        let rated = Double(snapshot.battery.adapterWatts)
        let long = period != .twoMinutes

        var seed: UInt64 = 7
        for unit in (key + period.rawValue).utf16 { seed = (seed * 31 + UInt64(unit)) & 0xFFFF_FFFF }
        func random() -> Double {
            seed = (seed * 1_664_525 + 1_013_904_223) & 0xFFFF_FFFF
            return Double(seed) / 4_294_967_296
        }

        let profiles: [String: (Double, Double)] = [
            "charging": (9, 38), "optimized": (8, 26), "temperature": (12, 34), "weak": (9, 27),
            "assist": (12, 47), "battery": (7, 19), "nobattery": (9, 30), "warming": (8, 26),
        ]
        let profile = profiles[key] ?? (9, 30)
        let bumpCount = period == .twoMinutes ? 2 : period == .oneHour ? 4 : 7
        let bumps: [(c: Double, w: Double, a: Double)] = (0..<bumpCount).map { _ in
            let c = random(), w = 0.015 + random() * 0.07, a = 0.4 + random() * 0.7
            return (c, w, a)
        }

        var raw: [Double] = []
        for i in 0..<n {
            let x = Double(i) / Double(n - 1)
            var value: Double
            if period == .twoMinutes {
                let noise = system * (0.9 + 0.2 * random())
                let bump = bumps.reduce(0) { $0 + $1.a * 6 * exp(-pow((x - $1.c) / $1.w, 2)) }
                value = noise + bump * (system > 15 ? 1 : 0.4)
            } else {
                let activity = min(1, bumps.reduce(0) { $0 + $1.a * exp(-pow((x - $1.c) / $1.w, 2)) })
                value = profile.0 + (profile.1 - profile.0) * activity + (random() - 0.5) * 1.6
            }
            if x > 0.94 {
                let k = (x - 0.94) / 0.06
                value = value * (1 - k) + system * k
            }
            raw.append(max(0.5, value))
        }
        let smooth = raw.indices.map { (raw[max(0, $0 - 1)] + raw[$0] + raw[min(n - 1, $0 + 1)]) / 3 }

        let hasAdapter = snapshot.battery.isPresent && snapshot.battery.isExternalConnected
        return smooth.enumerated().map { i, value in
            let x = Double(i) / Double(n - 1)
            if period == .day, x > 0.43, x < 0.70 { return nil }           // a noite, em repouso
            if fresh, long, Double(i) < Double(n) * (period == .day ? 0.99 : 0.7) { return nil }
            guard hasAdapter else { return (value, nil) }
            let adapter: Double
            switch key {
            case "charging":       adapter = min(rated - 2, value + 29)
            case "weak", "assist": adapter = min(input, value)
            case "temperature":    adapter = value + (long && x < 0.5 ? 20 : 0)
            default:               adapter = value + (long && x < 0.3 ? 18 * (1 - x / 0.3) : 0)
            }
            return (value, adapter)
        }
    }
}

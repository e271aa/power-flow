import AppKit
import Foundation
import PowerFlowCore

/// Imprime, a cada segundo, exatamente os valores que a interface mostra,
/// com as verificações de coerência entre eles. Usa o `PowerMonitor` real,
/// não uma reimplementação, para o que se vê aqui ser o que se vê no ecrã.
@MainActor
enum Watch {
    /// - Parameter fast: verdadeiro mede como com o painel aberto (10 Hz);
    ///   falso, como com ele fechado (1 Hz).
    static func run(seconds: Int, fast: Bool) {
        let monitor = PowerMonitor()
        monitor.setFastSampling(fast)
        print("  t   adapt.  sist.  bat.  | a->s   a->b   b->s  | soma  desvio | soc   ecra  outros")
        print(String(repeating: "-", count: 88))

        var tick = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick += 1
                report(monitor.snapshot, tick: tick)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(Double(seconds)))
        timer.invalidate()
    }

    private static func report(_ s: PowerSnapshot, tick: Int) {
        let adapter = s.source == .adapter ? (s.adapterInput ?? 0) : 0
        let system = s.systemTotal ?? 0
        let battery = s.adapterToBattery + s.batteryToSystem
        let outgoing = s.adapterToSystem + s.adapterToBattery

        // O que o nó do adaptador mostra tem de ser o que sai dele.
        let drift = adapter - outgoing

        let soc = s.socPower ?? 0
        let main = s.mainRailPower ?? 0
        let other = s.otherPower ?? 0

        print(String(format: "%3d  %6.2f %6.2f %5.2f | %5.2f  %5.2f  %5.2f | %5.2f %+6.2f | %4.1f %5.1f %6.1f",
                     tick, adapter, system, battery,
                     s.adapterToSystem, s.adapterToBattery, s.batteryToSystem,
                     outgoing, drift, soc, main, other))
    }
}

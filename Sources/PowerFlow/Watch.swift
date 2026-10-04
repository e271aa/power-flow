import AppKit
import Foundation
import PowerFlowCore

/// Imprime, a cada segundo, exatamente os valores que a interface mostra,
/// com as verificações de coerência entre eles. Usa o `PowerMonitor` real,
/// não uma reimplementação, para o que se vê aqui ser o que se vê no ecrã.
@MainActor
enum Watch {
    /// - Parameter fast: verdadeiro mede como com o painel aberto, ao ritmo
    ///   `rate` das Definições; falso, como com ele fechado (1 Hz).
    static func run(seconds: Int, fast: Bool, rate: SampleRate = AppSettings.sampleRate()) {
        let monitor = PowerMonitor(sampleRate: rate)
        monitor.setFastSampling(fast)
        var maxAssist = 0.0
        print("ritmo: \(fast ? (monitor.fastHz.map { "\($0) Hz" } ?? "1 Hz (Baixa)") : "1 Hz (painel fechado)")")
        print("  t   adapt.  sist.  bat.  | a->s   a->b   b->s  | soma  desvio | soc   ecra  outros")
        print(String(repeating: "-", count: 88))

        var tick = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick += 1
                report(monitor.snapshot, tick: tick)
                if monitor.snapshot.source == .adapter { maxAssist = max(maxAssist, monitor.snapshot.batteryToSystem) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(Double(seconds)))
        timer.invalidate()
        print(String(format: "assistência máxima mostrada com o cabo ligado: %.2f W", maxAssist))
    }

    /// Mede, a cada segundo e com o cabo ligado, os dois sinais que o alerta
    /// «bateria a ajudar» pode usar com o painel fechado, contra a referência
    /// alinhada a 10 Hz: a diferença consumo − entrada na média de 1 Hz (sem
    /// alinhamento de confiança, D5) e a corrente da bateria no IORegistry.
    /// No fim diz a sequência mais longa de segundos seguidos acima de 1,5 W
    /// em cada sinal: é ela que tem de ficar abaixo da espera do alerta.
    static func assist(seconds: Int) {
        let reference = PowerMonitor(sampleRate: .high)
        reference.setFastSampling(true)
        var slow = DualRateSmoother()
        let limit = PowerSnapshot.assistTolerance
        var runs = (slow: 0, ioreg: 0, ref: 0)
        var longest = (slow: 0, ioreg: 0, ref: 0)
        var peaks = (slow: 0.0, ioreg: 0.0, ref: 0.0)
        print("  t   sist.  entr. | lento s-e | ioreg A     V·A  | ref 10 Hz")
        print(String(repeating: "-", count: 66))

        var tick = 0
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                tick += 1
                slow.addSlow(PowerSampler.sampleRails())
                let avg = slow.average
                let battery = BatteryReader.read()
                guard battery.isExternalConnected else {
                    print(String(format: "%3d  (cabo desligado)", tick))
                    runs = (0, 0, 0)
                    return
                }
                let diff = (avg.systemTotal ?? 0) - (avg.adapterInput ?? 0)
                // Negativo a descarregar: é a bateria a dar ao sistema.
                let discharge = battery.amperage < 0 ? abs(battery.voltage * battery.amperage) : 0
                let ref = reference.snapshot.batteryToSystem

                runs.slow = diff > limit ? runs.slow + 1 : 0
                runs.ioreg = discharge > limit ? runs.ioreg + 1 : 0
                runs.ref = ref > limit ? runs.ref + 1 : 0
                longest = (max(longest.slow, runs.slow), max(longest.ioreg, runs.ioreg), max(longest.ref, runs.ref))
                peaks = (max(peaks.slow, diff), max(peaks.ioreg, discharge), max(peaks.ref, ref))
                print(String(format: "%3d  %5.1f  %5.1f | %+8.2f  | %+6.3f  %6.2f  | %6.2f",
                             tick, avg.systemTotal ?? 0, avg.adapterInput ?? 0, diff,
                             battery.amperage, discharge, ref))
                fflush(stdout)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(Double(seconds)))
        timer.invalidate()
        print(String(format: "pico           : lento %.2f W · ioreg %.2f W · ref %.2f W", peaks.slow, peaks.ioreg, peaks.ref))
        print("acima de 1,5 W, maior sequência: lento \(longest.slow) s · ioreg \(longest.ioreg) s · ref \(longest.ref) s")
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

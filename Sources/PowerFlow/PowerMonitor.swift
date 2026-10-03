import Combine
import Foundation
import IOKit.ps
import PowerFlowCore

/// Amostra o estado energético a 1 Hz e publica-o para a UI.
///
/// Além do temporizador, subscreve as notificações do IOKit para reagir de
/// imediato a ligar/desligar o cabo, em vez de esperar até um segundo.
@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot()
    @Published private(set) var isAvailable = false

    let history = PowerHistory()

    /// 30 amostras a 10 Hz (três segundos) e 9 de recuo (0.9 s) para alinhar
    /// a entrada com o consumo. Ver `PowerSmoother`.
    private var smoother = PowerSmoother(windowSize: 30, adapterDelay: 9)

    private var railTimer: Timer?
    private var snapshotTimer: Timer?
    private var runLoopSource: CFRunLoopSource?

    init() {
        isAvailable = SMCCatalog.shared.prepare()
        sample()
        start()
    }

    private func start() {
        // Leituras do SMC a 10 Hz, só para alimentar a média móvel. São
        // chamadas IOKit diretas e custam praticamente nada.
        let railTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.smoother.add(PowerSampler.sampleRails()) }
        }
        // Publicação para a interface a 1 Hz, que é quando a bateria também
        // é lida — essa leitura constrói um dicionário inteiro e é bem mais cara.
        let snapshotTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.sample() }
        }
        // .common para o diagrama não congelar enquanto há um menu aberto.
        RunLoop.main.add(railTimer, forMode: .common)
        RunLoop.main.add(snapshotTimer, forMode: .common)
        self.railTimer = railTimer
        self.snapshotTimer = snapshotTimer

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.sample() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    private func sample() {
        // Estado da bateria do instante, potências da média móvel. O
        // histórico recebe o mesmo valor que o diagrama, para o pico do
        // gráfico não contradizer o número mostrado nos nós.
        var fresh = PowerSnapshot()
        fresh.battery = BatteryReader.read()
        fresh.apply(smoother.average)
        fresh.isAligned = smoother.isAligned
        fresh.batteryMagnitude = abs(fresh.battery.voltage * fresh.battery.amperage)

        snapshot = fresh
        history.append(fresh)
    }

    deinit {
        railTimer?.invalidate()
        snapshotTimer?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }
}

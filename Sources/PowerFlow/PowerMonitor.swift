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

    /// O estado do painel para o instantâneo atual. As vistas recebem este.
    var panel: PanelState {
        PanelState(snapshot: snapshot, sensorsAvailable: isAvailable)
    }

    /// Três segundos de média e um de recuo para alinhar a entrada com o
    /// consumo, a 1 Hz ou a 10 Hz. Ver `DualRateSmoother`.
    private var smoother = DualRateSmoother()

    private var railTimer: Timer?
    private var snapshotTimer: Timer?
    private var runLoopSource: CFRunLoopSource?

    var isSamplingFast: Bool { railTimer != nil }

    init() {
        isAvailable = SMCCatalog.shared.prepare()
        tick()
        start()
    }

    /// Liga as leituras do SMC a 10 Hz, que alimentam a média do diagrama.
    /// Só fazem falta com o painel à vista; fechado, a app fica a 1 Hz.
    func setFastSampling(_ on: Bool) {
        guard on != isSamplingFast else { return }
        smoother.setFast(on)
        railTimer?.invalidate()
        railTimer = nil
        guard on else { return }

        // São chamadas IOKit diretas e custam praticamente nada.
        let railTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.smoother.addFast(PowerSampler.sampleRails()) }
        }
        // .common para o diagrama não congelar enquanto há um menu aberto.
        RunLoop.main.add(railTimer, forMode: .common)
        self.railTimer = railTimer
    }

    private func start() {
        // Publicação para a interface a 1 Hz, que é quando a bateria também
        // é lida — essa leitura constrói um dicionário inteiro e é bem mais cara.
        let snapshotTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(snapshotTimer, forMode: .common)
        self.snapshotTimer = snapshotTimer

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.publish() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    /// O passo de 1 Hz: uma leitura para a média lenta e uma publicação.
    private func tick() {
        smoother.addSlow(PowerSampler.sampleRails())
        publish()
    }

    private func publish() {
        // Estado da bateria do instante, potências da média móvel. O
        // histórico recebe o mesmo valor que o diagrama, para o pico do
        // gráfico não contradizer o número mostrado nos nós.
        var fresh = PowerSnapshot()
        fresh.battery = BatteryReader.read()
        if fresh.source != snapshot.source { smoother.sourceChanged() }
        fresh.apply(smoother.average)
        fresh.isAligned = smoother.isAligned
        fresh.isSettled = smoother.isSettled
        fresh.settleRemaining = smoother.settleRemaining
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

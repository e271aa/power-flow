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

    /// O histórico nos três períodos. Só a app da barra o grava em disco.
    let history: HistoryStore

    /// O estado do painel para o instantâneo atual. As vistas recebem este.
    var panel: PanelState {
        PanelState(snapshot: snapshot, sensorsAvailable: isAvailable)
    }

    /// Três segundos de média e um de recuo para alinhar a entrada com o
    /// consumo, ao ritmo lento ou ao rápido. Ver `DualRateSmoother`.
    private var smoother = DualRateSmoother()

    private var railTimer: Timer?
    private var snapshotTimer: Timer?
    private var runLoopSource: CFRunLoopSource?

    /// Os números mudam no máximo 2 vezes por segundo: o tique de 1 Hz e o
    /// aviso do sistema juntos chegaram a publicar três vezes no mesmo segundo.
    private var gate = PublishGate()
    private var publishPending = false
    /// Uma aresta que se apaga espera 1 s de estabilidade.
    private var edgeHold = EdgeHold()

    /// O painel está à vista: é só então que o ritmo das Definições conta.
    private var panelIsOpen = false
    /// O ritmo escolhido nas Definições para o painel aberto.
    private(set) var sampleRate: SampleRate
    /// As leituras por segundo do ritmo rápido em curso; `nil` com ele parado.
    private(set) var fastHz: Int?

    var isSamplingFast: Bool { railTimer != nil }

    /// `persistsHistory`: lê e grava as 24 h em disco. As ferramentas de linha
    /// de comandos e a janela `--window` ficam só com a memória.
    init(persistsHistory: Bool = false, sampleRate: SampleRate = AppSettings.sampleRate()) {
        self.sampleRate = sampleRate
        history = HistoryStore(fileURL: persistsHistory ? HistoryStore.defaultFileURL : nil)
        isAvailable = SMCCatalog.shared.prepare()
        tick()
        start()
    }

    /// Liga as leituras do SMC ao ritmo escolhido, que alimentam a média do
    /// diagrama. Só fazem falta com o painel à vista; fechado, a app fica a 1 Hz.
    func setFastSampling(_ on: Bool) {
        panelIsOpen = on
        applySampling()
    }

    /// A frequência escolhida nas Definições. Com o painel aberto muda já.
    func setSampleRate(_ rate: SampleRate) {
        guard rate != sampleRate else { return }
        sampleRate = rate
        applySampling()
    }

    private func applySampling() {
        let wanted = panelIsOpen ? sampleRate.fastHz : nil
        guard wanted != fastHz else { return }
        fastHz = wanted
        railTimer?.invalidate()
        railTimer = nil
        guard let hz = wanted else {
            smoother.setFast(false)
            return
        }
        smoother.setFast(true, hz: hz)

        // São chamadas IOKit diretas e custam praticamente nada.
        let railTimer = Timer(timeInterval: 1 / Double(hz), repeats: true) { [weak self] _ in
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
            Task { @MainActor in monitor.requestPublish() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    /// O passo de 1 Hz: uma leitura para a média lenta e uma publicação.
    private func tick() {
        smoother.addSlow(PowerSampler.sampleRails())
        requestPublish()
    }

    /// Publica já, ou assim que passarem 0,5 s desde a última publicação.
    private func requestPublish() {
        let wait = gate.wait(at: Date())
        if wait == 0 {
            publish()
        } else if !publishPending {
            publishPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                MainActor.assumeIsolated {
                    self?.publishPending = false
                    self?.publish()
                }
            }
        }
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
        fresh.heldEdges = edgeHold.held(for: fresh, at: fresh.timestamp)

        gate.published(at: Date())
        snapshot = fresh
        // Sem leitura do consumo não há ponto: fica uma lacuna, não um zero.
        if let system = fresh.systemTotal {
            let adapter = fresh.source == .adapter && fresh.battery.isPresent ? fresh.adapterInput : nil
            // Fechou um intervalo de 10 min: é a altura de gravar.
            if history.append(system: system, adapter: adapter, at: fresh.timestamp) {
                saveHistory()
            }
        }
    }

    /// Grava as 24 h. Chama-se de 10 em 10 min e ao sair.
    func saveHistory() {
        do {
            try history.save()
        } catch {
            NSLog("PowerFlow: não foi possível gravar o histórico: \(error.localizedDescription)")
        }
    }

    deinit {
        railTimer?.invalidate()
        snapshotTimer?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }
}

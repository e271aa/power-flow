import XCTest
@testable import PowerFlowCore

/// Os sete estados do painel e a prioridade dos avisos, pela tabela
/// «Quando aparece cada estado» do handoff. Não lê sensores.
final class PanelStateTests: XCTestCase {
    private let optimized = 16_777_216
    private let temperature = 16
    private let weakAdapter = 1024
    private let standby = 128

    /// Um portátil ligado à corrente, com a média já alinhada.
    private func plugged(input: Double, total: Double, charging: Bool = false,
                         reason: Int = 0) -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = true
        snapshot.battery.isCharging = charging
        snapshot.battery.notChargingReason = reason
        snapshot.battery.percentage = 80
        snapshot.adapterInput = input
        snapshot.systemTotal = total
        return snapshot
    }

    private func unplugged(total: Double) -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = false
        snapshot.systemTotal = total
        return snapshot
    }

    private func state(_ snapshot: PowerSnapshot, sensors: Bool = true) -> PanelState {
        PanelState(snapshot: snapshot, sensorsAvailable: sensors)
    }

    // MARK: - Os sete estados

    func testA1ACarregar() {
        var snapshot = plugged(input: 60, total: 20, charging: true)
        snapshot.battery.minutesRemaining = 48

        let panel = state(snapshot)
        XCTAssertEqual(panel.kind, .charging)
        XCTAssertEqual(panel.origin, .adapter)
        XCTAssertNil(panel.banner)
        XCTAssertEqual(panel.time, .untilFull(minutes: 48))
        XCTAssertEqual(panel.batteryActivity, .charging)
        XCTAssertTrue(panel.showsBattery)
    }

    func testA2EmPausa() {
        let panel = state(plugged(input: 10, total: 10, reason: optimized))
        XCTAssertEqual(panel.kind, .paused)
        XCTAssertEqual(panel.origin, .adapter)
        XCTAssertEqual(panel.banner, .optimized)
        XCTAssertEqual(panel.time, PanelState.Time.none)
        XCTAssertEqual(panel.batteryActivity, .idle)
    }

    func testA3BateriaAAjudar() {
        let panel = state(plugged(input: 29.6, total: 41.8))
        XCTAssertEqual(panel.kind, .assisting)
        XCTAssertEqual(panel.origin, .adapterAndBattery)
        XCTAssertEqual(panel.banner, .assist)
        XCTAssertEqual(panel.time, PanelState.Time.none)
        XCTAssertEqual(panel.batteryActivity, .supplying)
    }

    func testA4EmBateria() {
        var snapshot = unplugged(total: 12.2)
        snapshot.battery.minutesRemaining = 284

        let panel = state(snapshot)
        XCTAssertEqual(panel.kind, .onBattery)
        XCTAssertEqual(panel.origin, .battery)
        XCTAssertNil(panel.banner)
        XCTAssertEqual(panel.time, .remaining(minutes: 284))
        XCTAssertEqual(panel.batteryActivity, .supplying)
    }

    func testA5SemBateria() {
        var snapshot = PowerSnapshot()
        snapshot.systemTotal = 8.5

        let panel = state(snapshot)
        XCTAssertEqual(panel.kind, .noBattery)
        XCTAssertEqual(panel.origin, .mains)
        XCTAssertNil(panel.banner)
        XCTAssertEqual(panel.time, PanelState.Time.none)
        XCTAssertFalse(panel.showsBattery)
    }

    func testA6SensoresIndisponiveis() {
        let panel = state(plugged(input: 60, total: 20, charging: true), sensors: false)
        XCTAssertEqual(panel.kind, .unavailable)
        XCTAssertNil(panel.banner)
        XCTAssertEqual(panel.time, PanelState.Time.none)
        XCTAssertFalse(panel.showsBattery)
    }

    func testA7AEstabilizar() {
        var snapshot = plugged(input: 10, total: 10, reason: optimized)
        snapshot.isAligned = false
        snapshot.isSettled = false

        let panel = state(snapshot)
        XCTAssertEqual(panel.kind, .settling)
        XCTAssertEqual(panel.origin, .adapter)
        XCTAssertNil(panel.banner, "nunca há aviso durante a estabilização")
        XCTAssertEqual(panel.time, PanelState.Time.none)
        XCTAssertTrue(panel.showsBattery)
    }

    // MARK: - A ordem da tabela

    func testSensoresIndisponiveisGanhamATudo() {
        var snapshot = unplugged(total: 12)
        snapshot.isSettled = false
        XCTAssertEqual(state(snapshot, sensors: false).kind, .unavailable)
    }

    func testEstabilizarGanhaAoEstadoDaEnergia() {
        var snapshot = unplugged(total: 12)
        snapshot.isSettled = false
        XCTAssertEqual(state(snapshot).kind, .settling)
        XCTAssertEqual(state(snapshot).origin, .battery)
    }

    func testAjudarGanhaACarregar() {
        // O registo ainda diz «a carregar», mas o sistema já pede mais do
        // que o adaptador dá.
        let panel = state(plugged(input: 30, total: 42, charging: true))
        XCTAssertEqual(panel.kind, .assisting)
    }

    func testBateriaCheiaFicaEmPausaSemAviso() {
        var snapshot = plugged(input: 10, total: 10)
        snapshot.battery.isFullyCharged = true
        snapshot.battery.percentage = 100

        let panel = state(snapshot)
        XCTAssertEqual(panel.kind, .paused)
        XCTAssertNil(panel.banner)
        XCTAssertEqual(panel.batteryActivity, .idle)
    }

    // MARK: - Prioridade dos avisos

    func testPrioridade1BateriaAAjudar() {
        let all = temperature | weakAdapter | optimized
        let panel = state(plugged(input: 20, total: 32, reason: all))
        XCTAssertEqual(panel.banner, .assist)
        XCTAssertEqual(panel.banner?.isAttention, true)
    }

    func testPrioridade2Temperatura() {
        let all = temperature | weakAdapter | optimized
        let panel = state(plugged(input: 20, total: 20, reason: all))
        XCTAssertEqual(panel.banner, .temperature)
        XCTAssertEqual(panel.banner?.isAttention, true)
    }

    func testPrioridade3AdaptadorFraco() {
        let panel = state(plugged(input: 20, total: 20, reason: weakAdapter | optimized))
        XCTAssertEqual(panel.banner, .weakAdapter)
        XCTAssertEqual(panel.banner?.isAttention, true)
    }

    func testPrioridade4CargaOtimizada() {
        let panel = state(plugged(input: 20, total: 20, reason: optimized | standby))
        XCTAssertEqual(panel.banner, .optimized)
        XCTAssertEqual(panel.banner?.isAttention, false)
    }

    func testEmEsperaSoSozinho() {
        let panel = state(plugged(input: 20, total: 20, reason: standby))
        XCTAssertEqual(panel.banner, .standby)
        XCTAssertEqual(panel.banner?.isAttention, false)
    }

    /// Com o painel acabado de abrir há números, mas a diferença entre
    /// entrada e consumo ainda não é de confiança. O painel mostra o estado
    /// normal, sem assistência, em vez de voltar a «A estabilizar».
    func testAcabadoDeAbrirNaoEstabilizaNemInventaAssistencia() {
        var snapshot = plugged(input: 20, total: 32, reason: optimized)
        snapshot.isAligned = false

        let panel = state(snapshot)
        XCTAssertEqual(panel.kind, .paused)
        XCTAssertEqual(panel.origin, .adapter)
        XCTAssertEqual(panel.banner, .optimized)
        XCTAssertEqual(panel.batteryActivity, .idle)
    }

    // MARK: - D5: o limiar de «bateria a ajudar»

    func testAbaixoDoLimiarNaoHaAvisoNemDuasOrigens() {
        // 1 W de diferença é ruído da leitura: nem aviso, nem dois pontos.
        let panel = state(plugged(input: 20, total: 21, reason: optimized))
        XCTAssertEqual(panel.kind, .paused)
        XCTAssertEqual(panel.origin, .adapter)
        XCTAssertEqual(panel.banner, .optimized)
        XCTAssertEqual(panel.batteryActivity, .idle)
    }

    // MARK: - E3: o tempo só aparece onde faz sentido

    /// O bug: «17 h 37 min restantes» por cima de «Ligado à corrente». Com
    /// a carga em pausa, o IORegistry pode trazer um `TimeRemaining` antigo.
    func testE3SemTempoRestanteComOCaboLigado() {
        var snapshot = plugged(input: 10, total: 10, reason: optimized)
        snapshot.battery.minutesRemaining = 1057

        XCTAssertEqual(state(snapshot).time, PanelState.Time.none)
    }

    func testE3ACarregarOTempoEAteEncherENaoRestante() {
        var snapshot = plugged(input: 60, total: 20, charging: true)
        snapshot.battery.minutesRemaining = 48

        XCTAssertEqual(state(snapshot).time, .untilFull(minutes: 48))
    }

    func testE3SemLeituraNaoHaTempo() {
        XCTAssertEqual(state(unplugged(total: 12)).time, PanelState.Time.none)
    }
}

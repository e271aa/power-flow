import XCTest
@testable import PowerFlowCore

/// Os alertas (secção E do handoff), com relógio falso: cada um dispara uma
/// vez por episódio e só se rearma depois de 5 min seguidos sem a condição.
final class AlertMonitorTests: XCTestCase {
    private let nb = PFFormat.nbsp

    /// Um relógio que só anda quando o teste manda.
    private final class FakeClock {
        var now = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { now += seconds }
    }

    private var clock = FakeClock()
    private var monitor = AlertMonitor()

    override func setUp() {
        clock = FakeClock()
        let clock = clock
        monitor = AlertMonitor(clock: { clock.now })
    }

    /// Ligado à corrente, carga parada, com a média de 1 Hz do painel fechado
    /// (sem alinhamento de confiança).
    private func plugged(input: Double = 30, total: Double = 20, temperature: Double? = 31,
                         reason: Int = 0, charging: Bool = false) -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        snapshot.battery.isPresent = true
        snapshot.battery.isExternalConnected = true
        snapshot.battery.isCharging = charging
        snapshot.battery.notChargingReason = reason
        snapshot.battery.adapterWatts = 67
        snapshot.adapterInput = input
        snapshot.systemTotal = total
        snapshot.batteryTemperature = temperature
        snapshot.isAligned = false
        return snapshot
    }

    private var assisting: PowerSnapshot { plugged(input: 30, total: 42) }
    private var calm: PowerSnapshot { plugged(input: 20, total: 20) }
    private var hot: PowerSnapshot { plugged(temperature: 45) }
    private var weak: PowerSnapshot { plugged(input: 20, total: 20, reason: 1024) }

    private func everythingOn() -> AlertSettings {
        var settings = AlertSettings()
        settings.weakAdapter = true
        return settings
    }

    /// Avança `seconds` segundos, uma leitura por segundo, e devolve os alertas que dispararam.
    @discardableResult
    private func run(_ snapshot: PowerSnapshot, for seconds: Int,
                     settings: AlertSettings? = nil) -> [AlertKind] {
        var fired: [AlertKind] = []
        for _ in 0..<seconds {
            clock.advance(1)
            fired += monitor.update(snapshot: snapshot, sensorsAvailable: true,
                                    settings: settings ?? everythingOn(), language: "pt-PT").map(\.kind)
        }
        return fired
    }

    // MARK: - Uma vez por episódio

    /// O padrão dos três: condição, aviso ao fim da espera, nada enquanto dura,
    /// uma falha curta não abre episódio novo, 5 min sem ela rearmam.
    private func assertOncePerEpisode(_ kind: AlertKind, active: PowerSnapshot, delay: Int,
                                      file: StaticString = #filePath, line: UInt = #line) {
        setUp()
        // A primeira leitura com a condição abre o pendente; a espera conta dali.
        XCTAssertEqual(run(active, for: delay), [], "antes da espera", file: file, line: line)
        XCTAssertEqual(monitor.phase(kind), .pending(since: clock.now - Double(delay - 1)), file: file, line: line)
        XCTAssertEqual(run(active, for: 1), [kind], "ao fim da espera", file: file, line: line)
        XCTAssertEqual(run(active, for: 600), [], "a condição continua: nada", file: file, line: line)

        // Desaparece 4 min 59 s e volta: o mesmo episódio.
        XCTAssertEqual(run(calm, for: 299), [], file: file, line: line)
        if case .rearming = monitor.phase(kind) {} else { XCTFail("devia estar a rearmar", file: file, line: line) }
        XCTAssertEqual(run(active, for: 600), [], "voltou antes dos 5 min: sem segundo aviso", file: file, line: line)

        // 5 min seguidos sem a condição rearmam; o episódio seguinte avisa outra vez.
        XCTAssertEqual(run(calm, for: 301), [], file: file, line: line)
        XCTAssertEqual(monitor.phase(kind), .idle, "rearmado ao fim de 5 min", file: file, line: line)
        XCTAssertEqual(run(active, for: delay + 1), [kind], "episódio novo, aviso novo", file: file, line: line)
    }

    func testBateriaAAjudarDisparaUmaVezPorEpisodio() {
        assertOncePerEpisode(.assist, active: assisting, delay: 30)
    }

    func testBateriaQuenteDisparaUmaVezPorEpisodio() {
        assertOncePerEpisode(.temperature, active: hot, delay: 60)
    }

    func testAdaptadorFracoDisparaUmaVezPorEpisodio() {
        assertOncePerEpisode(.weakAdapter, active: weak, delay: 120)
    }

    func testRearmaSoComCincoMinutosSeguidosSemACondicao() {
        XCTAssertEqual(run(assisting, for: 31), [.assist])
        // Três ausências de 4 min, separadas por um segundo com a condição:
        // somam 12 min sem ela, mas nenhuma chega aos 5 min seguidos.
        for _ in 0..<3 {
            XCTAssertEqual(run(calm, for: 240), [])
            XCTAssertEqual(run(assisting, for: 1), [])
        }
        XCTAssertEqual(monitor.phase(.assist), .fired)
    }

    func testCondicaoInterrompidaRecomecaAEspera() {
        XCTAssertEqual(run(assisting, for: 30), [])
        XCTAssertEqual(run(calm, for: 1), [])
        XCTAssertEqual(monitor.phase(.assist), .idle)
        XCTAssertEqual(run(assisting, for: 30), [], "a espera recomeçou do zero")
        XCTAssertEqual(run(assisting, for: 1), [.assist])
    }

    // MARK: - Esperas e limites das Definições

    func testAEsperaDaAssistenciaSegueAsDefinicoes() {
        for delay in AlertSettings.assistDelays {
            setUp()
            var settings = everythingOn()
            settings.assistDelay = delay
            XCTAssertEqual(run(assisting, for: delay, settings: settings), [], "\(delay) s")
            XCTAssertEqual(run(assisting, for: 1, settings: settings), [.assist], "\(delay) s")
        }
    }

    func testOLimiteDeTemperaturaSegueAsDefinicoes() {
        var settings = everythingOn()
        settings.temperatureLimit = 46
        XCTAssertEqual(run(hot, for: 120, settings: settings), [], "45 °C não passa de 46")
        settings.temperatureLimit = 44
        XCTAssertEqual(run(hot, for: 61, settings: settings), [.temperature])
    }

    func testUmAlertaDesligadoNaoDisparaEEsqueceOEpisodio() {
        var off = everythingOn()
        off.assist = false
        XCTAssertEqual(run(assisting, for: 300, settings: off), [])
        XCTAssertEqual(monitor.phase(.assist), .idle)

        // Ligado a meio de um episódio já avisado, volta a contar do zero.
        XCTAssertEqual(run(assisting, for: 31), [.assist])
        run(assisting, for: 1, settings: off)
        XCTAssertEqual(run(assisting, for: 31), [.assist])
    }

    func testOAdaptadorFracoVemDesligadoPorOmissao() {
        XCTAssertEqual(run(weak, for: 300, settings: AlertSettings()), [])
    }

    // MARK: - Condições

    /// A 1 Hz o desalinhamento numa rampa de carga dá picos de 1–3 s acima de
    /// 1,5 W (medido: 2 s no arranque). Não podem chegar à espera mínima.
    func testPicosCurtosDeAssistenciaNaoDisparam() {
        var settings = everythingOn()
        settings.assistDelay = 10
        for _ in 0..<60 {
            XCTAssertEqual(run(assisting, for: 3, settings: settings), [])
            XCTAssertEqual(run(calm, for: 1, settings: settings), [])
        }
    }

    func testAssistenciaPedeMaisDe1_5W() {
        XCTAssertFalse(AlertMonitor.condition(.assist, snapshot: plugged(input: 30, total: 31.5),
                                              sensorsAvailable: true, settings: AlertSettings()))
        XCTAssertTrue(AlertMonitor.condition(.assist, snapshot: plugged(input: 30, total: 31.6),
                                             sensorsAvailable: true, settings: AlertSettings()))
    }

    func testAssistenciaNaoExisteEmBateriaNemAEstabilizarNemSemSensores() {
        var unplugged = assisting
        unplugged.battery.isExternalConnected = false
        var settling = assisting
        settling.isSettled = false
        var noBattery = assisting
        noBattery.battery.isPresent = false
        for snapshot in [unplugged, settling, noBattery] {
            XCTAssertFalse(AlertMonitor.condition(.assist, snapshot: snapshot,
                                                  sensorsAvailable: true, settings: AlertSettings()))
        }
        XCTAssertFalse(AlertMonitor.condition(.assist, snapshot: assisting,
                                              sensorsAvailable: false, settings: AlertSettings()))
    }

    /// Com o painel fechado não há `isAligned` e o `batteryToSystem` do
    /// diagrama é zero; o alerta tem de ver a assistência na mesma.
    func testAssistenciaVistaComOPainelFechado() {
        XCTAssertEqual(assisting.batteryToSystem, 0)
        XCTAssertEqual(AlertMonitor.assistWatts(assisting), 12)
    }

    func testAdaptadorFracoPorRazaoOuPorEntradaNoLimite() {
        let settings = AlertSettings()
        XCTAssertTrue(AlertMonitor.condition(.weakAdapter, snapshot: weak, sensorsAvailable: true, settings: settings))
        // 65 W de 67 W com a carga parada.
        XCTAssertTrue(AlertMonitor.condition(.weakAdapter, snapshot: plugged(input: 65, total: 65),
                                             sensorsAvailable: true, settings: settings))
        XCTAssertFalse(AlertMonitor.condition(.weakAdapter, snapshot: plugged(input: 64.9, total: 64.9),
                                              sensorsAvailable: true, settings: settings))
        // A carregar, o adaptador no limite está só a trabalhar.
        XCTAssertFalse(AlertMonitor.condition(.weakAdapter, snapshot: plugged(input: 66, total: 30, charging: true),
                                              sensorsAvailable: true, settings: settings))
    }

    func testSemBateriaNaoHaAlertas() {
        var snapshot = hot
        snapshot.battery.isPresent = false
        snapshot.battery.notChargingReason = 1024
        for kind in AlertKind.allCases {
            XCTAssertFalse(AlertMonitor.condition(kind, snapshot: snapshot, sensorsAvailable: true,
                                                  settings: everythingOn()), "\(kind)")
        }
    }

    // MARK: - Lacunas (Mac a dormir)

    /// Uma hora sem leituras não conta como uma hora com a condição.
    func testUmaLacunaNaoContaComoEspera() {
        run(assisting, for: 5)
        clock.advance(3600)
        XCTAssertEqual(run(assisting, for: 1), [], "acordou com a condição: a espera recomeça")
        XCTAssertEqual(run(assisting, for: 30), [.assist])
    }

    func testUmaLacunaNaoContaComoRearme() {
        XCTAssertEqual(run(assisting, for: 31), [.assist])
        run(calm, for: 10)
        clock.advance(3600)
        XCTAssertEqual(run(calm, for: 1), [])
        if case .rearming = monitor.phase(.assist) {} else { XCTFail("ainda a rearmar") }
        run(calm, for: 300)
        XCTAssertEqual(monitor.phase(.assist), .idle)
    }

    // MARK: - Textos

    func testOsTextosLevamOsNumerosReais() {
        let assist = AlertMonitor.event(.assist, snapshot: plugged(input: 30.4, total: 41.6), language: "pt-PT")
        XCTAssertEqual(assist.title, "A bateria está a ajudar o adaptador")
        XCTAssertEqual(assist.body, "O Mac pede 42\(nb)W e o adaptador dá 30\(nb)W. Liga um adaptador mais potente.")

        let hotPaused = AlertMonitor.event(.temperature, snapshot: plugged(temperature: 42.3, reason: 16), language: "pt-PT")
        XCTAssertEqual(hotPaused.title, "Bateria quente: 42\(nb)°C")
        XCTAssertEqual(hotPaused.body, "A carga parou até arrefecer. Deixa as saídas de ar livres.")

        var onBattery = plugged(temperature: 42.3)
        onBattery.battery.isExternalConnected = false
        let hotUnplugged = AlertMonitor.event(.temperature, snapshot: onBattery, language: "en")
        XCTAssertEqual(hotUnplugged.title, "Battery hot: 42\(nb)°C")
        XCTAssertEqual(hotUnplugged.body, "Keep the vents clear so the battery can cool.",
                       "sem pausa pelo calor não se diz que a carga parou")

        let weakEvent = AlertMonitor.event(.weakAdapter, snapshot: plugged(input: 20, total: 18.2), language: "en")
        XCTAssertEqual(weakEvent.title, "Adapter too weak for this load")
        XCTAssertEqual(weakEvent.body, "The 67\(nb)W adapter can’t charge while your Mac uses 18\(nb)W.")
    }

    // MARK: - Definições

    private func freshDefaults() -> UserDefaults {
        let name = "pf.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testOmissoesDosAlertasSaoAsDoHandoff() {
        let settings = AppSettings.alerts(freshDefaults())
        XCTAssertTrue(settings.assist)
        XCTAssertEqual(settings.assistDelay, 30)
        XCTAssertTrue(settings.temperature)
        XCTAssertEqual(settings.temperatureLimit, 40)
        XCTAssertFalse(settings.weakAdapter)
    }

    func testOsAlertasPersistemPelasChavesDoHandoff() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "pf.alert.assist")
        defaults.set(120, forKey: "pf.alert.assistDelay")
        defaults.set(false, forKey: "pf.alert.temp")
        defaults.set(47, forKey: "pf.alert.tempLimit")
        defaults.set(true, forKey: "pf.alert.weak")
        let settings = AppSettings.alerts(defaults)
        XCTAssertFalse(settings.assist)
        XCTAssertEqual(settings.assistDelay, 120)
        XCTAssertFalse(settings.temperature)
        XCTAssertEqual(settings.temperatureLimit, 47)
        XCTAssertTrue(settings.weakAdapter)
    }

    func testValoresForaDoMenuVoltamAOmissaoOuAoLimite() {
        let defaults = freshDefaults()
        defaults.set(45, forKey: "pf.alert.assistDelay")
        defaults.set(80, forKey: "pf.alert.tempLimit")
        let settings = AppSettings.alerts(defaults)
        XCTAssertEqual(settings.assistDelay, 30)
        XCTAssertEqual(settings.temperatureLimit, 50)
    }

    func testOCartaoDePrimeiroArranqueSoAteAoPercebi() {
        let defaults = freshDefaults()
        XCTAssertFalse(AppSettings.firstRunDone(defaults))
        defaults.set(true, forKey: AppSettings.firstRunDoneKey)
        XCTAssertTrue(AppSettings.firstRunDone(defaults))
        XCTAssertEqual(AppSettings.firstRunDoneKey, "pf.firstRunDone")
    }
}

/// O passo do «Acima de»: os botões − e + das Definições.
final class TemperatureStepTests: XCTestCase {
    func testUmPassoAndaUmGrau() {
        XCTAssertEqual(AlertSettings.steppedTemperatureLimit(40, by: 1), 41)
        XCTAssertEqual(AlertSettings.steppedTemperatureLimit(40, by: -1), 39)
    }

    func testNosExtremosFicaOndeEsta() {
        XCTAssertEqual(AlertSettings.steppedTemperatureLimit(35, by: -1), 35)
        XCTAssertEqual(AlertSettings.steppedTemperatureLimit(50, by: 1), 50)
        // Os dois botões desativam-se nos extremos porque o passo não muda nada.
        XCTAssertEqual(AlertSettings.steppedTemperatureLimit(36, by: -1), 35)
        XCTAssertEqual(AlertSettings.steppedTemperatureLimit(49, by: 1), 50)
    }
}

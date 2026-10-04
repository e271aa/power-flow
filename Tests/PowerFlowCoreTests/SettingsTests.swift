import XCTest
@testable import PowerFlowCore

/// As Definições (`pf.*`), o título da barra e o ritmo de amostragem.
final class SettingsTests: XCTestCase {
    private let nb = PFFormat.nbsp

    private func freshDefaults() -> UserDefaults {
        let name = "pf.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    // MARK: - Preferências

    func testOmissoesSaoAsDoHandoff() {
        let defaults = freshDefaults()
        XCTAssertEqual(AppSettings.barMode(defaults), .iconWatts)
        XCTAssertEqual(AppSettings.sampleRate(defaults), .normal)
    }

    func testAsEscolhasPersistemPelasChavesDoHandoff() {
        let defaults = freshDefaults()
        defaults.set("iconPercent", forKey: "pf.barMode")
        defaults.set("high", forKey: "pf.sampleRate")
        XCTAssertEqual(AppSettings.barMode(defaults), .iconPercent)
        XCTAssertEqual(AppSettings.sampleRate(defaults), .high)
        // O que a vista escreve é o que o item lê.
        XCTAssertEqual(AppSettings.barModeKey, "pf.barMode")
        XCTAssertEqual(AppSettings.sampleRateKey, "pf.sampleRate")
    }

    func testUmValorDesconhecidoVoltaAOmissao() {
        let defaults = freshDefaults()
        defaults.set("lixo", forKey: "pf.barMode")
        defaults.set("lixo", forKey: "pf.sampleRate")
        XCTAssertEqual(AppSettings.barMode(defaults), .iconWatts)
        XCTAssertEqual(AppSettings.sampleRate(defaults), .normal)
    }

    func testFrequenciaDeAmostragem() {
        XCTAssertNil(SampleRate.low.fastHz, "Baixa: com o painel aberto fica a 1 Hz")
        XCTAssertEqual(SampleRate.normal.fastHz, 2)
        XCTAssertEqual(SampleRate.high.fastHz, 10)
    }

    // MARK: - Título

    private func snapshot(watts: Double?, percent: Int = 80, battery: Bool = true) -> PowerSnapshot {
        var s = PowerSnapshot()
        s.systemTotal = watts
        s.battery.isPresent = battery
        s.battery.percentage = percent
        return s
    }

    func testOsQuatroModos() {
        XCTAssertEqual(BarTitle.content(mode: .icon, hasBattery: true), .empty)
        XCTAssertEqual(BarTitle.content(mode: .iconWatts, hasBattery: true), .watts)
        XCTAssertEqual(BarTitle.content(mode: .watts, hasBattery: true), .watts)
        XCTAssertEqual(BarTitle.content(mode: .iconPercent, hasBattery: true), .percent)
        XCTAssertTrue(BarMode.icon.showsIcon)
        XCTAssertTrue(BarMode.iconWatts.showsIcon)
        XCTAssertTrue(BarMode.iconPercent.showsIcon)
        XCTAssertFalse(BarMode.watts.showsIcon, "«Só watts» não tem ícone")
    }

    func testSemBateriaAPercentagemCaiNosWatts() {
        XCTAssertEqual(BarTitle.content(mode: .iconPercent, hasBattery: false), .watts)
    }

    func testTextoDoTitulo() {
        let s = snapshot(watts: 36.4)
        XCTAssertEqual(BarTitle.text(.watts, snapshot: s, language: "pt-PT"), "36\(nb)W")
        XCTAssertEqual(BarTitle.text(.percent, snapshot: s, language: "pt-PT"), "80\(nb)%")
        XCTAssertEqual(BarTitle.text(.empty, snapshot: s, language: "pt-PT"), "")
    }

    func testSemLeituraNaoHaZeroInventado() {
        XCTAssertEqual(BarTitle.text(.watts, snapshot: snapshot(watts: nil), language: "pt-PT"), "—")
    }

    func testDicaSemSensores() {
        XCTAssertEqual(BarTitle.toolTip(snapshot: snapshot(watts: nil), sensorsAvailable: false, language: "pt-PT"),
                       "PowerFlow — sensores indisponíveis")
        XCTAssertTrue(BarTitle.toolTip(snapshot: snapshot(watts: 36), sensorsAvailable: true, language: "pt-PT")
            .contains("36,0\(nb)W"))
    }

    // MARK: - No máximo de 2 em 2 s

    func testOTituloNaoMudaMaisDeUmaVezEm2s() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(throttle.shown(for: "10 W", at: t0), "10 W")
        // Leituras a 1 Hz, sempre diferentes: o texto mostrado segura 2 s.
        XCTAssertEqual(throttle.shown(for: "11 W", at: t0 + 1), "10 W")
        XCTAssertEqual(throttle.shown(for: "12 W", at: t0 + 1.99), "10 W")
        XCTAssertEqual(throttle.shown(for: "13 W", at: t0 + 2), "13 W")
        XCTAssertEqual(throttle.shown(for: "14 W", at: t0 + 3), "13 W")
        XCTAssertEqual(throttle.shown(for: "15 W", at: t0 + 4), "15 W")
    }

    func testMudancasSeguidasNuncaFicamAMenosDe2s() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        var changes: [TimeInterval] = []
        var last: String?
        // 120 s de leituras a 4 Hz, com o texto a mudar em todas.
        for step in 0..<480 {
            let t = Double(step) * 0.25
            let shown = throttle.shown(for: "\(step) W", at: t0 + t)
            if shown != last { changes.append(t); last = shown }
        }
        let gaps = zip(changes, changes.dropFirst()).map { $1 - $0 }
        XCTAssertGreaterThan(changes.count, 30)
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, 2)
    }

    func testOTextoIgualNaoReinicia() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = throttle.shown(for: "10 W", at: t0)
        _ = throttle.shown(for: "10 W", at: t0 + 1.5)
        // Passaram 2 s desde a mudança, não desde a última leitura.
        XCTAssertEqual(throttle.shown(for: "11 W", at: t0 + 2), "11 W")
    }

    func testMudarDeModoPassaLogo() {
        var throttle = BarTitleThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = throttle.shown(for: "36 W", at: t0)
        XCTAssertEqual(throttle.shown(for: "80 %", at: t0 + 0.1, immediately: true), "80 %")
        // E a contagem recomeça aí.
        XCTAssertEqual(throttle.shown(for: "81 %", at: t0 + 1), "80 %")
    }

    // MARK: - Ritmo de amostragem

    private func rails(input: Double, total: Double) -> RailReading {
        var reading = RailReading()
        reading.adapterInput = input
        reading.systemTotal = total
        return reading
    }

    /// A 2 Hz a janela são 3 s (6 amostras) e o recuo 1 s (2 amostras).
    func testA2HzAJanelaSaoOsMesmos3sEORecuoOMesmo1s() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }
        smoother.setFast(true, hz: 2)
        XCTAssertEqual(smoother.fastHz, 2)

        for _ in 0..<7 { smoother.addFast(rails(input: 50, total: 40)) }
        XCTAssertFalse(smoother.isAligned, "6 + 2 amostras para encher")
        smoother.addFast(rails(input: 50, total: 40))
        XCTAssertTrue(smoother.isAligned)
        XCTAssertEqual(smoother.average.systemTotal ?? 0, 40, accuracy: 0.001)
    }

    func testA2HzUmaRampaDeCargaNaoParecAssistencia() {
        var smoother = DualRateSmoother()
        smoother.setFast(true, hz: 2)
        // 10 W parados e uma rampa de 15 W por amostra; o consumo repete a
        // entrada duas amostras (1 s) mais tarde.
        let input = (0..<30).map { 10 + 15 * Double(max(0, $0 - 10)) }
        for index in input.indices {
            smoother.addFast(rails(input: input[index], total: input[max(0, index - 2)]))
        }
        XCTAssertEqual(smoother.average.systemTotal ?? 0, smoother.average.adapterInput ?? -1, accuracy: 0.001)
    }

    func testMudarOHzRecomecaAJanela() {
        var smoother = DualRateSmoother()
        for _ in 0..<4 { smoother.addSlow(rails(input: 20, total: 18)) }
        smoother.setFast(true, hz: 10)
        for _ in 0..<40 { smoother.addFast(rails(input: 50, total: 40)) }
        XCTAssertTrue(smoother.isAligned)

        smoother.setFast(true, hz: 2)
        XCTAssertFalse(smoother.isAligned, "as amostras de 10 Hz não servem a 2 Hz")
        XCTAssertEqual(smoother.fastHz, 2)
    }

    func testOTempoParaEstabilizarSegueOHz() {
        var smoother = DualRateSmoother()
        smoother.setFast(true, hz: 2)
        // Nenhuma leitura lenta: a rápida são 8 amostras a 2 Hz, 4 s; a lenta, 4 s também.
        XCTAssertEqual(smoother.settleRemaining, 4, accuracy: 0.001)
    }
}
